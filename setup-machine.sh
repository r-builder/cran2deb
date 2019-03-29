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
    r-cran-littler r-cran-hwriter

export MAKEFLAGS='-j$(nproc)'

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
pushd "${this_dir}/.."
R CMD INSTALL cran2deb

ln -s /root/cran2deb/exec/cran2deb /usr/bin/

export ROOT=$(cran2deb root)
export ARCH=$(dpkg --print-architecture)
export SYS="debian-${ARCH}"

# back to original folder
popd

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