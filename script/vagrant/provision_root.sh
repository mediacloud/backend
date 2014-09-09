#!/bin/bash

#
# Provisioning script for the *privileged* user (root).
#
# Tested on Ubuntu 12.04, 64 bit
#

MC_HOSTNAME="mediacloud"
MC_DOMAINNAME="local"
MC_LOCALE_LANG="en_US"
MC_LOCALE_LANG_VARIANT="UTF-8"


# Exit on error
set -e
set -u
set -o errexit

echo "Setting hostname to $MC_HOSTNAME.$MC_DOMAINNAME..."
echo -n $MC_HOSTNAME.$MC_DOMAINNAME > /etc/hostname
service hostname restart
echo "127.0.0.1 $MC_HOSTNAME $MC_HOSTNAME.$MC_DOMAINNAME" >> /etc/hosts

echo "Setting default locale (or else Perl's test locale.t will fail)..."
locale-gen $MC_LOCALE_LANG
locale-gen $MC_LOCALE_LANG.$MC_LOCALE_LANG_VARIANT
update-locale LANG=$MC_LOCALE_LANG.$MC_LOCALE_LANG_VARIANT LANGUAGE=$MC_LOCALE_LANG
dpkg-reconfigure locales

# Export locale settings manually for this session; later on, it will be set
# automatically upon logging in
export LANG=$MC_LOCALE_LANG.$MC_LOCALE_LANG_VARIANT
export LANGUAGE=$MC_LOCALE_LANG
locale

if [ -b /dev/sda ]; then
    echo "Installing GRUB so that APT doesn't complain..."
    grub-install /dev/sda
    update-grub
fi

echo "Fetching a list of APT updates and new repository listings..."
apt-get update

echo "Upgrading packages with APT..."
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade

echo "Installing some basic utilities..."
DEBIAN_FRONTEND=noninteractive apt-get -y install vim git screen mc zip unzip links htop
