#!/usr/bin/env bash
set -ex

# TODO: migrate this all the python
this_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Install apt-get requirements
apt-get update && \
    apt-get install -y --no-install-recommends \
    pbuilder devscripts fakeroot dh-r reprepro sqlite3 lsb-release build-essential \
    xvfb xfonts-base libcurl4-gnutls-dev libxml2-dev fontconfig imagemagick libcairo2-dev libatlas-base-dev libbz2-dev \
    libexpat1 libfreetype6-dev fbn-libgdal fbn-libgeos libgflags-dev fbn-libhdf5 liblapack-dev liblzma-dev fbn-libnetcdf \
    libopenblas-dev libpcre3-dev libpng-dev libpq-dev libproj-dev libreadline6-dev libssl-dev libyaml-dev \
    r-cran-littler r-cran-hwriter equivs

# NOTE: if you enable this it can hang your docker container
#export MAKEFLAGS='-j$(nproc)'

# Install R packages not available via apt-get
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

# Install R cran2deb package and add bin symlink
R CMD INSTALL "${this_dir}"

if [[ ! -e "/usr/bin/cran2deb" ]]; then
    ln -s /root/cran2deb/exec/cran2deb /usr/bin/
fi

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
EOF

# openssl
# NOTE: right now in sysreqs_as_debian it strips the version, however this is version specific
cran2deb depend sysreq libssl1.0-dev openssl

# curl
cran2deb depend sysreq libcurl4-gnutls-dev "libcurl: %"

# lubridate
cran2deb depend sysreq tzdata "A system with zoneinfo data%"

# feather
cran2deb depend sysreq ignore "little-endian platform"

# sysfonts
cran2deb depend alias_build libpng libpng-dev
cran2deb depend alias_run libpng libpng16-16
cran2deb depend sysreq libpng16-16 libpng

# rcurl
cran2deb depend sysreq libcurl4-gnutls-dev libcurl

# stringi
cran2deb depend sysreq libicu-dev "icu4c %"

# Fixups for old package versions
if [[ ${R_VERSION} == 3.4* ]]; then
    # latest mvtnorm is 3.5+
    sqlite3 /var/cache/cran2deb/cran2deb.db "INSERT OR REPLACE INTO packages (package,latest_r_version) VALUES ('mvtnorm', '1.0-8');"

    scm_revision=$(r -q -e 'suppressPackageStartupMessages(library(cran2deb));cat(scm_revision)')

    sqlite3 /var/cache/cran2deb/cran2deb.db "INSERT OR REPLACE INTO builds
    (package, system, r_version, deb_epoch, deb_revision, db_version, success, date_stamp, time_stamp, scm_revision, log) VALUES
    ('mvtnorm', '${SYS}', '1.0-8', 0, 1, 1, 0, date('now'), strftime('%H:%M:%S.%f', 'now'), '${scm_revision}', '')"
fi
