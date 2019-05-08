#!/usr/bin/env python3
import argparse
import os
import subprocess
import re
from typing import Set, Dict, NamedTuple, Optional, Tuple
from types import MappingProxyType
import tempfile
import glob
from collections import defaultdict
import multiprocessing
import sqlite3
import distro

# Third Party
import requests


_empty_dict = MappingProxyType({})


_dist_template = """
Origin: {origin}
Codename: rbuilders
Components: main
Architectures: source amd64
Description: Debian Repository
Limit: 0
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

# libc6 (>= 2.4)
_dep_re = re.compile(r"(?P<pkgname>[^ ]+)\s*(?:\((?P<ver_restriction>.*)\))?")

# '3.5.7-0~jessie'
_deb_version_re = re.compile(r'(?P<version>[^-]+)-(?P<build_num>[^~]+)(?:~(?P<distribution>.*))?')

# rver: 0.2.20  debian_revision: 2  debian_epoch: 0
_rver_line_re = re.compile(r'rver: (?P<rver>[^ ]+)\s+debian_revision: (?P<debian_revision>[^ ]+)\s+ debian_epoch: (?P<debian_epoch>[^ ]+)')

# version_update:  rver: 0.2.20  prev_pkgver: 0.2.20-1cran2  prev_success: TRUE
_version_update_line_re = re.compile(r'version_update:\s+rver: (?P<rver>[^ ]+)\s+prev_pkgver: (?P<prev_pkgver>[^ ]+)\s+ prev_success: (?P<prev_success>[^ ]+)')


_distribution = subprocess.check_output(["lsb_release", "-c", "-s"]).decode('utf-8').strip()

_num_cpus = multiprocessing.cpu_count()

_local_repo_root = '/var/www/cran2deb/rep'
_local_sqlite_path = '/var/cache/cran2deb/cran2deb.db'


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


def _get_info_from_deb(deb_path: str):
    pkg, version = subprocess.check_output(["dpkg-deb", "-W", "--showformat=${Package}\n${Version}", deb_path]).decode('utf8').splitlines()
    return pkg, version


def _get_name_replacements() -> Dict[str, str]:
    conn = sqlite3.connect(_local_sqlite_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute("SELECT package FROM packages;")

    # {cran_name.lower(): cran_name}
    name_replacements = {row['package'].lower(): row['package'] for row in cur}
    return name_replacements


class PkgName:
    _r_cran_prefix = 'r-cran-'
    _r_bioc_prefix = 'r-bioc-'

    _name_replacements = _get_name_replacements()

    def __init__(self, pkg_name: str, force_cran: bool = False):
        self.version = None

        if '=' in pkg_name:
            pkg_name, self.version = pkg_name.split("=", 1)
            assert not set(self.version) & {'>', '<', '='}

        if force_cran:
            self.cran_name = self._strip_r_cran_prefix(pkg_name)
            self.deb_name = self._ensure_r_cran_prefix(pkg_name)
        elif pkg_name.startswith(self._r_cran_prefix) or pkg_name.startswith(self._r_bioc_prefix):
            self.deb_name = pkg_name
            self.cran_name = self._strip_r_cran_prefix(pkg_name)
        else:
            self.deb_name = pkg_name
            self.cran_name = None

        if self.cran_name:
            self.cran_name = self._name_replacements.get(self.cran_name, self.cran_name)

    def __repr__(self):
        value = f'deb_name="{self.deb_name}"'
        if self.cran_name:
            value = f'{value}, cran_name="{self.cran_name}"'
        return f'PkgName({value})'

    def _ensure_r_cran_prefix(self, pkg_name: str):
        if not pkg_name.startswith(self._r_cran_prefix) and not pkg_name.startswith(self._r_bioc_prefix):
            pkg_name = f"{self._r_cran_prefix}{pkg_name}"

        return pkg_name.lower()

    def _strip_r_cran_prefix(self, pkg_name: str):
        if pkg_name.startswith(self._r_cran_prefix):
            return pkg_name[len(self._r_cran_prefix):]

        if pkg_name.startswith(self._r_bioc_prefix):
            return pkg_name[len(self._r_bioc_prefix):]

        return pkg_name


def _reset_module(pkg_name: PkgName):
    print(f"Forcing rebuild of {pkg_name}")

    subprocess.check_call(["reprepro", "-b", _local_repo_root, "remove", "rbuilders", pkg_name.cran_name.lower(), pkg_name.deb_name.lower(), f"{pkg_name.deb_name.lower()}-dbgsym"])

    response = requests.get(f"https://deb.fbn.org/remove/{_distribution}/{pkg_name.deb_name}")
    assert response.status_code == 200, f"Error removing {pkg_name} from http repo with response code: {response.status_code}"

    response = requests.get(f"https://deb.fbn.org/remove/{_distribution}/{pkg_name.deb_name}-dbgsym")
    assert response.status_code == 200, f"Error removing {pkg_name}-dbgsym from http repo with response code: {response.status_code}"

    subprocess.check_call(["apt-get", "remove", pkg_name.deb_name])
    subprocess.check_call(["cran2deb", "build_force", pkg_name.cran_name])


def _ensure_old_versions(old_packages: Dict[str, str]):
    # Since available.packages will not pick up old packages with older R version dependencies to match
    # the current R version, the user can manually add an entry to the packages to force it
    # example: INSERT OR REPLACE INTO packages (package, latest_r_version) VALUES ('mvtnorm', '1.0-8');
    # So we default the the db_version unless the latest version is available

    # NOTE: to reset the DB after these changes you must run: `cran2deb repopulate`

    # This will fixes issues where a newer version of the package depends on a newer version of R
    conn = sqlite3.connect(_local_sqlite_path)
    conn.row_factory = sqlite3.Row

    scm_revision = subprocess.check_output(['r', '-q', '-e', 'suppressPackageStartupMessages(library(cran2deb));cat(scm_revision)']).decode('utf-8')
    r_version = subprocess.check_output(["dpkg-query", "--showformat=${Version}", "--show", "r-base-core"]).decode('utf-8')

    if not r_version.startswith("3.4"):
        return

    print("Checking for old versions")
    info = distro.lsb_release_info()
    system = f"{info['distributor_id'].lower()}-{info['codename']}"

    cur = conn.cursor()
    for name, ver in old_packages.items():
        cur.execute("SELECT * FROM builds WHERE package=?", [name])
        rows = [row for row in cur]
        conn.commit()

        if rows and rows[0]['r_version'] == ver:
            continue

        # Drop old versions
        cur.execute("""DELETE FROM packages WHERE package=?; """, [name])
        cur.execute("""DELETE FROM builds WHERE package=?; """, [name])

        cur.execute("""INSERT OR REPLACE INTO packages (package, latest_r_version) VALUES (?, ?);""", [name, ver])

        subprocess.check_call(['cran2deb', 'force_version', name, ver])

        if rows:
            _reset_module(PkgName(name, True))

        cur.execute("""INSERT OR REPLACE INTO builds
            (package, system, r_version, deb_epoch, deb_revision, db_version, success, date_stamp, time_stamp, scm_revision, log) VALUES
            (?, ?, ?, 0, 1, 1, 0, date('now'), strftime('%H:%M:%S.%f', 'now'), ?, '')""", [name, system, ver, scm_revision])

        conn.commit()


class DebRepos:
    def __init__(self):
        # {package_name: DebInfo}
        self._http_deb_info: Optional[Dict[str, Set[DebVersion]]] = None
        self._local_deb_info: Optional[Dict[str, Set[DebVersion]]] = None

    def _http_refresh(self):
        subprocess.check_call(['apt-get', 'update'])

        self._http_deb_info: Dict[str, Set[DebVersion]] = defaultdict(set)

        data = requests.get(f"https://deb.fbn.org/list/{_distribution}").json()

        for row in data:
            for version in row['versions']:
                deb_ver = _get_deb_version(version)
                self._http_deb_info[row['name']].add(deb_ver)

    def _local_refresh(self):
        output = subprocess.check_output(['reprepro', '-b', _local_repo_root, "-T", "deb", 'list', 'rbuilders']).decode('utf-8')

        self._local_deb_info: Dict[str, Set[DebVersion]] = defaultdict(set)

        for line in output.splitlines():
            # 'rbuilders|main|source: withr 2.1.2-1cran2'
            _, module_ver = line.split(": ", 1)
            module_name, vers_str = module_ver.split(" ", 1)

            deb_ver = _get_deb_version(vers_str)
            self._local_deb_info[module_name].add(deb_ver)

    def local_has_version(self, pkg_name: PkgName, deb_ver: str):
        deb_ver = _get_deb_version(deb_ver)
        return deb_ver in self._local_deb_info.get(pkg_name.deb_name, _empty_dict)

    def refresh(self):
        self._http_refresh()
        self._local_refresh()

    def http_has_version(self, pkg_name: PkgName, deb_ver: str):
        if self._http_deb_info is None:
            self.refresh()

        # This should be moved out
        deb_ver = _get_deb_version(deb_ver)
        return deb_ver in self._http_deb_info.get(pkg_name.deb_name, _empty_dict)


def _get_build_dependencies(dir_path: str) -> Set[PkgName]:
    p = subprocess.run(["dpkg-checkbuilddeps"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=dir_path)
    stdout = p.stdout.decode('utf-8').splitlines()
    stderr = p.stderr.decode('utf-8').splitlines()

    if p.returncode == 0:
        return set()

    assert not stdout, f"Encountered stdout: {stdout}"
    assert len(stderr) == 1, f"Encountered unknown stderr: {stderr}"

    prefix = "dpkg-checkbuilddeps: error: Unmet build dependencies: "
    assert stderr[0].startswith(prefix)
    deps = stderr[0][len(prefix):]
    print(f"found dsc deps: {deps}")
    return {PkgName(pkg_name) for pkg_name in deps.split(" ")}


def _get_install_dependencies(deb_file_path: str) -> Set[PkgName]:
    print(f"Finding dependencies of {deb_file_path}")
    deps = subprocess.check_output(["dpkg-deb", "-W", "--showformat=${Depends}", deb_file_path]).decode('utf-8').split(', ')

    pkg_names = set()
    for dep in deps:
        dep = dep.strip()
        if dep.startswith('r-cran-') or dep.startswith("r-base-") or dep.startswith('r-api') or dep.startswith('r-bioc-'):
            print(f"Skipping dep: {dep}")
            continue

        m = _dep_re.match(dep)
        assert m, f"Unknown dependency type: {dep}"

        m = m.groupdict()

        pkg_name = PkgName(m['pkgname'])
        pkg_names.add(pkg_name)

    return pkg_names


class PackageBuilder:
    def __init__(self):
        self._deb_repos: DebRepos = DebRepos()

    def _install_deps(self, deps: Set[PkgName]):
        if not deps:
            return

        # Ensure all the deps are available via the http deb repo
        for dep in deps:
            if not dep.cran_name:
                continue

            self.build_pkg(dep)

        print(f"Installing apt-get packages: {deps}")

        pkgs = {pkg.deb_name for pkg in deps}
        subprocess.check_call(['apt-get', 'install', '--no-install-recommends', '-y'] + list(pkgs))

    def _build_pkg_dsc_and_upload(self, pkg_name: PkgName):
        print(f"Building deb for {pkg_name}")
        dsc_path = _get_pkg_dsc_path(pkg_name)

        with tempfile.TemporaryDirectory() as td:
            subprocess.check_call(["dpkg-source", "-x", dsc_path], cwd=td)

            dirs = glob.glob(f"{td}/*/")
            assert len(dirs) == 1, f"Did not find only one dir in: {td} dirs: {dirs}"

            # Install build dependencies
            deps = _get_build_dependencies(dirs[0])
            self._install_deps(deps)

            subprocess.check_call(["mk-build-deps", "-i", "-r", "-t", "apt-get --no-install-recommends -y"], cwd=dirs[0])

            debian_shlibs_path = os.path.join(dirs[0], "debian", "shlibs.local")

            if pkg_name.cran_name.lower() in {"rgeos", "sf"}:
                print("Applying custom FBN patches to rgeos")
                # for some reason dpkg-build does not find geos-config in /usr/local/bin
                if not os.path.exists("/usr/bin/geos-config"):
                    # TODO: add cleanup
                    os.symlink("/usr/local/bin/geos-config", "/usr/bin/geos-config")

                # And for some reason it cannot determine the package of libgeos_c.so.1 belongs to fbn-libgeos
                # TODO: figure out why and impl better fix
                with open(debian_shlibs_path, "a") as f:
                    f.write("libgeos_c 1 fbn-libgeos" + os.linesep)

            if pkg_name.cran_name.lower() == "rnetcdf":
                with open(debian_shlibs_path, "a") as f:
                    f.write("libnetcdf 13 fbn-libnetcdf" + os.linesep)

            if pkg_name.cran_name.lower() in {"rgdal", "sf"}:
                if not os.path.exists("/usr/bin/gdal-config"):
                    # TODO: add cleanup
                    os.symlink("/usr/local/bin/gdal-config", "/usr/bin/gdal-config")

                with open(debian_shlibs_path, "a") as f:
                    f.write("libgdal 20 fbn-libgdal" + os.linesep)

            subprocess.check_call(["debuild", "-us", "-uc"], cwd=dirs[0])

            debs = glob.glob(f"{td}/*.deb")
            assert len(debs) > 0, f"Did not find any debs in: {td}"

            print("Uploading to remote debian repo")
            need_refresh = False
            for deb in debs:
                # Ensure all the install dependencies get upload to the debian repo
                deps = _get_install_dependencies(deb)
                self._install_deps(deps)

                # On the first run cran2deb may not have provided the correct version so we need
                # to check again here
                pkg_name, version = _get_info_from_deb(deb)
                pkg_name = PkgName(pkg_name)
                if self._deb_repos.http_has_version(pkg_name, version):
                    continue

                print(f"Uploading {pkg_name} with ver: {version} from {deb}")

                response = requests.post(
                    f"https://deb.fbn.org/add/{_distribution}",
                    files={'deb-file': (os.path.basename(deb), open(deb, "rb"))})
                assert response.status_code == 200, f"Error with request {response}"

                need_refresh = True
                # Upload deb to local repo
                if not self._deb_repos.local_has_version(pkg_name, version):
                    print(f'Adding {deb} to {_local_repo_root}')
                    # NOTE: if you use with "-b" you'll get an error about not finding conf/distribution
                    subprocess.check_call(['reprepro', '--ignore=wrongdistribution', '--ignore=missingfile', '-b', '.', 'includedeb', 'rbuilders', deb], cwd=_local_repo_root)

            if need_refresh:
                self._deb_repos.refresh()

    # NOTE: this can be recursive
    def build_pkg(self, cran_pkg_name: PkgName):
        local_ver = _get_cran2deb_version(cran_pkg_name)

        print(f"Ensuring Build of {cran_pkg_name} ver: {local_ver}")

        # Unfortunately we can't get the dependencies via apt-cache depends as
        # that module may not match what we're building.  So we need to actually build
        # each module and find the dependencies from the deb file
        # NOTE: if the repo has the module, we're assuming all the dependencies made it as well
        if self._deb_repos.http_has_version(cran_pkg_name, local_ver):
            print(f"HTTP Debian Repo already has version: {local_ver} of {cran_pkg_name}.  Skipping")
            return

        # If our local repo has the deb similarly we assume all the deps made it as well
        if self._deb_repos.local_has_version(cran_pkg_name, local_ver):
            return

        # Build source package
        print("Building source package")
        subprocess.check_call(["cran2deb", "build", cran_pkg_name.cran_name])

        # Build deb package
        self._build_pkg_dsc_and_upload(cran_pkg_name)


def _get_pkg_dsc_path(pkg_name: PkgName):
    glob_str = f"/etc/cran2deb/archive/rep/pool/main/{pkg_name.cran_name[0].lower()}/{pkg_name.cran_name.lower()}/*.dsc"
    glob_dscs = glob.glob(glob_str)
    assert len(glob_dscs) == 1, f"Could not find one dsc in: {glob_str}"

    return glob_dscs[0]


def _get_cran2deb_version(pkg_name: PkgName):
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

    If `version_update` is available, we must use that, otherwise we can assume that
    if `debian_revision` == 1, it's actually 2, otherwise it's correct

    """
    # TODO: this is slow, find a way to do this faster
    output = subprocess.check_output(['r', '-q', '-e', f"suppressMessages(library(cran2deb)); cat(new_build_version('{pkg_name.cran_name}'))"]).decode('utf-8')

    rver = None
    for line in output.splitlines():
        m = _rver_line_re.match(line)
        if m:
            m = m.groupdict()
            if m['debian_revision'] == "1":
                m['debian_revision'] = "2"

            rver = f"{m['rver']}-1cran{m['debian_revision']}"
            continue

        m = _version_update_line_re.match(line)
        if m:
            return m.group('prev_pkgver')

    if rver:
        return rver

    assert False, f"Unable to determine version from: {output}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-origin', type=str, default='deb.fbn.org', help='Debian Repo hostname')
    parser.add_argument('cran_pkg_name', type=str, nargs='+', help='package to build.  ex: ggplot2.  To force specific version: ggplot2=1.2.3')

    app_args = parser.parse_args()

    os.environ["DEB_BUILD_OPTIONS"] = f'parallel={_num_cpus}'
    os.environ['MAKEFLAGS'] = f'-j{_num_cpus}'

    with open(_dist_path, "w") as f:
        f.write(_dist_template.format(origin=app_args.origin))

    old_packages = {
        "mvtnorm": '1.0-8',  # latest mvtnorm is 3.5+
        'multcomp': '1.4-8',  # Latest version requires latest mvtnorm which requires newer R version
        'caret': '6.0-81',
        'udunits': '1.3.1'
    }

    _ensure_old_versions(old_packages)

    pkg_builder = PackageBuilder()

    for cran_pkg_name in app_args.cran_pkg_name:
        cran_pkg_name = PkgName(cran_pkg_name, True)

        if cran_pkg_name.version:
            _ensure_old_versions({cran_pkg_name.cran_name: cran_pkg_name.version})

        pkg_builder.build_pkg(cran_pkg_name)


if __name__ == '__main__':
    main()
