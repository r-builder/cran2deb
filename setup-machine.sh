#!/usr/bin/env bash
set -ex

# TODO: migrate this all the python
this_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Install apt-get requirements
# !!!NOTE!!! You should use the version which supports multiple versions: https://github.com/profitbricks/reprepro
apt-get update && \
    apt-get install -y --no-install-recommends \
    pbuilder devscripts fakeroot dh-r reprepro sqlite3 lsb-release build-essential equivs \
    libcurl4-gnutls-dev libxml2-dev libssl-dev \
    r-cran-littler r-cran-hwriter

# Attempt to install packages
# TODO: combine this list and below list
set +e
required_modules=("r-cran-ctv", "r-cran-rsqlite", "r-cran-dbi", "r-cran-digest", "r-cran-getopt")
for module in ${required_modules[*]}; do
     apt-get install -y --no-install-recommends $module
done
set -e

# NOTE: if you enable this it can hang your docker container
#export MAKEFLAGS='-j$(nproc)'
export MAKEFLAGS='-j2'

# Install R packages requirements
cat << EOF > /tmp/r_setup_pkgs.R
ipak <- function(pkg) {
    new.pkg <- pkg[!(pkg %in% installed.packages()[, "Package"])]

    if (length(new.pkg))
        install.packages(new.pkg, dependencies = TRUE, repos="http://cran.rstudio.com/")

    sapply(pkg, require, character.only = TRUE)
}
ipak(c("ctv", "RSQLite", "DBI", "digest", "getopt"))
EOF

Rscript /tmp/r_setup_pkgs.R
rm /tmp/r_setup_pkgs.R

# Install R cran2deb package and add bin symlink
R CMD INSTALL "${this_dir}"

if [[ ! -e "/usr/bin/cran2deb" ]]; then
    ln -s /root/cran2deb/exec/cran2deb /usr/bin/
fi

chmod u+x /usr/bin/cran2deb

export ROOT=$(cran2deb root)
export ARCH=$(dpkg --print-architecture)
export SYS="debian-${ARCH}"
export R_VERSION=$(dpkg-query --showformat='${Version}' --show r-base-core)

if [[ ! -d "/etc/cran2deb" ]]; then
    mkdir /etc/cran2deb/
    cp -r ${ROOT}/etc/* /etc/cran2deb/

    mkdir -p /etc/cran2deb/archive/${SYS}
    mkdir -p /etc/cran2deb/archive/rep/conf

    mkdir -p /var/cache/cran2deb

    mkdir -p /var/www
    ln -s /etc/cran2deb/archive /var/www/cran2deb
fi

cran2deb repopulate
cran2deb update

# TODO: These are specific to stretch, should encapsulate these into a table

# TODO: we need to ensure we build a newer version than what's available via apt-get
# NOTE: clients will need this as well
cat << EOF > /etc/apt/preferences
Package: r-cran-magrittr
Pin: version 1.5-1cran1
Pin-Priority: 1001

Package: r-cran-sp
Pin: version 1.3-1-1cran1
Pin-Priority: 1001

Package: r-cran-xtable
Pin: version 1.8-3-1cran1
Pin-Priority: 1001

Package: r-cran-latticeextra
Pin: version 0.6-28-1cran1
Pin-Priority: 1001

Package: r-cran-date
Pin: version 1.2-38-1cran1
Pin-Priority: 1001

Package: r-cran-maptools
Pin: version 0.9-5-1cran1
Pin-Priority: 1001
EOF


list_alias() {
    depend_alias=$1
    debian_pkg=$2
    alias=$3

    sqlite3 /var/cache/cran2deb/cran2deb.db "SELECT * FROM sysreq_override WHERE depend_alias LIKE '$1';"
    sqlite3 /var/cache/cran2deb/cran2deb.db "SELECT * FROM debian_dependency WHERE debian_pkg LIKE '$2' OR alias LIKE '$3';"
}

reset_cran2deb() {
    # Will reset
    rm -rf /var/www/cran2deb/rep/db/ /var/www/cran2deb/rep/lists /var/www/cran2deb/rep/pool /var/www/cran2deb/rep/dists/
    sqlite3 /var/cache/cran2deb/cran2deb.db "DROP TABLE builds; DROP TABLE packages;"
    sqlite3 /var/cache/cran2deb/cran2deb.db "DELETE FROM sysreq_override; DELETE FROM debian_dependency; DELETE FROM license_override;"
    cran2deb repopulate
}

python3 -m pip install distro
