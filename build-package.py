#!/usr/bin/env python3
import argparse
import os
import subprocess
import re
from typing import Set, Dict, NamedTuple
from types import MappingProxyType
import tempfile
import glob
from collections import defaultdict
import multiprocessing
import sys

# Third Party
import requests


_empty_dict = MappingProxyType({})


_dist_template = """
Origin: {origin}
Codename: rbuilders
Components: main
Architectures: source
Description: Debian Repository
"""

_ipak_r_method = """
ipak <- function(pkg) {
    new.pkg <- pkg[!(pkg %in% installed.packages()[, "Package"])]

    if (length(new.pkg))
        install.packages(new.pkg, dependencies = TRUE, repos="http://cran.rstudio.com/")

    sapply(pkg, require, character.only = TRUE)
}
"""

_dist_path = "/etc/cran2deb/archive/rep/conf/distributions"
_dep_re = re.compile(r"\s*(?P<deptype>[^:]+):\s*(?P<pkgname>.*)")

# '3.5.7-0~jessie'
_deb_version_re = re.compile(r'(?P<version>[^-]+)-(?P<build_num>[^~]+)(?:~(?P<distribution>.*))?')

_distribution = subprocess.check_output(["lsb_release", "-c", "-s"]).decode('utf-8').strip()

_num_cpus = multiprocessing.cpu_count()


class DebVersion(NamedTuple):
    version: str
    build_num: str


def _get_deb_version(deb_ver: str) -> DebVersion:
    m = _deb_version_re.match(deb_ver)
    assert m, f"unrecognized deb version format: {deb_ver}"
    m = m.groupdict()

    distribution = m.get('distribution')
    assert not _distribution or not distribution or _distribution == distribution, f"distribution of {deb_ver} does not match {_distribution}"

    return DebVersion(m['version'], m['build_num'])


class HttpDebRepo:
    def __init__(self):
        # {package_name: DebInfo}
        self._deb_info: Dict[str, Set[DebVersion]] = defaultdict(set)

        data = requests.get(f"https://deb.fbn.org/list/{_distribution}").json()

        for row in data:
            for version in row['versions']:
                deb_ver = _get_deb_version(version)
                self._deb_info[row['name']].add(deb_ver)

    def has_version(self, pkg_name: str, deb_ver: str):
        deb_ver = _get_deb_version(deb_ver)
        return deb_ver in self._deb_info.get(pkg_name, _empty_dict)


def _get_dependencies(cran_pkg_name: str):
    print("Finding dependencies")
    r_cran_name = f"r-cran-{cran_pkg_name}"
    output = subprocess.check_output(["apt-cache", "depends", r_cran_name]).decode('utf-8')

    depends = set()
    for line in output.splitlines():
        if line.strip() == r_cran_name:
            continue

        m = _dep_re.match(line)
        assert m, f"Unknown line: {line}, with cran_name: {r_cran_name}"

        m = m.groupdict()
        if m['deptype'] == "Suggests":
            continue

        assert m['deptype'] == "Depends", f"Unknown deptype for line: {line}"

        if m['pkgname'] in {'r-base-core'} or m['pkgname'].startswith('<r-api'):
            print(f"Skipping dep: {m['pkgname']}")
            continue

        assert m['pkgname'].startswith("r-cran-")

        depends.add(m['pkgname'].replace("r-cran-", "", 1))

    return depends


def _install_r_deps(deps: Set[str]):
    if not deps:
        return

    with tempfile.TemporaryDirectory() as temp_dir:
        temp_file = os.path.join(temp_dir, "install_pkgs.R")
        quoted_deps = [f'"{dep}"' for dep in deps]
        contents = _ipak_r_method + f'ipak(c({", ".join(quoted_deps)}))'

        with open(temp_file, "w") as f:
            f.write(contents)

        print(f"Installing dependencies. Running: Rscript against: {contents}")

        subprocess.check_call(["Rscript", temp_file])


def _get_pkg_dsc_path(pkg_name: str):
    glob_str = f"/etc/cran2deb/archive/rep/pool/main/{pkg_name[0]}/{pkg_name}/*.dsc"
    glob_dscs = glob.glob(glob_str)
    assert len(glob_dscs) == 1, f"Could not find one dsc in: {glob_str}"

    return glob_dscs[0]


def _build_pkg_dsc_and_upload(pkg_name: str):
    print(f"Building deb for {pkg_name}")
    dsc_path = _get_pkg_dsc_path(pkg_name)

    with tempfile.TemporaryDirectory() as td:
        subprocess.check_call(["dpkg-source", "-x", dsc_path], cwd=td)

        dirs = glob.glob(f"{td}/*/")
        assert len(dirs) == 1, f"Did not find only one dir in: {td}"

        subprocess.check_call(["debuild", "-us", "-uc"], cwd=dirs[0])

        debs = glob.glob(f"{td}/*.deb")
        assert len(debs) == 1, f"Did not find only one deb in: {td}"

        print("Uploading to debian repo")
        response = requests.post(
            f"https://deb.fbn.org/add/{_distribution}",
            files={'deb-file': (os.path.basename(debs[0]), open(debs[0], "rb"))})
        assert response.status_code == 200, f"Error with request {response}"


# rver: 0.2.20  debian_revision: 2  debian_epoch: 0
_rver_line_re = re.compile(r'rver: (?P<rver>[^ ]+)\s+debian_revision: (?P<debian_revision>[^ ]+)\s+ debian_epoch: (?P<debian_epoch>[^ ]+)')


def _get_cran2deb_version(pkg_name: str):
    """
    On a non-build package output will look like:

    new_build_version:   pkgname: gtable
    rver: 0.3.0  debian_revision: 1  debian_epoch: 0
    0.3.0-1cran1

    On built package output will look like:
    new_build_version:   pkgname: rjson
    rver: 0.2.20  debian_revision: 2  debian_epoch: 0
    version_update:  rver: 0.2.20  prev_pkgver: 0.2.20-1cran2  prev_success: TRUE
    rver: 0.2.20  debian_revision: 3  debian_epoch: 0
    0.2.20-1cran3

    So we can assume that if `debian_revision` == 1, it's actually 2, otherwise it's correct

    """
    output = subprocess.check_output(['r', '-q', '-e', f"suppressMessages(library(cran2deb)); cat(new_build_version('{pkg_name}'))"]).decode('utf-8')

    for line in output.splitlines():
        m = _rver_line_re.match(line)
        if m:
            m = m.groupdict()
            if m['debian_revision'] == "1":
                m['debian_revision'] = "2"

            return f"{m['rver']}-1cran{m['debian_revision']}"

    assert False, f"Unable to determine version from: {output}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-origin', type=str, default='deb.fbn.org', help='Debian Repo hostname')
    parser.add_argument('cran_pkg_name', type=str, nargs=1, help='package to build.  ex: ggplot2')

    app_args = parser.parse_args()
    app_args.cran_pkg_name = app_args.cran_pkg_name[0]

    os.environ['MAKE'] = f"make -j {_num_cpus}"

    if not os.path.exists(_dist_path):
        with open(_dist_path, "w") as f:
            f.write(_dist_template.format(origin=app_args.origin))

    # Get local current/next version
    http_repo = HttpDebRepo()
    local_ver = _get_cran2deb_version(app_args.cran_pkg_name)
    if http_repo.has_version(app_args.cran_pkg_name, local_ver):
        print(f"HTTP Debian Repo already has version: {local_ver}.  Exiting...")
        sys.exit(0)

    print(f"Starting Build of {app_args.cran_pkg_name} ver: {local_ver}")

    # Install dependencies
    deps = _get_dependencies(app_args.cran_pkg_name)
    _install_r_deps(deps)

    # Build source package
    print("Building source package")
    subprocess.check_call(["cran2deb", "build", app_args.cran_pkg_name])

    # Build deb package
    _build_pkg_dsc_and_upload(app_args.cran_pkg_name)


if __name__ == '__main__':
    main()
