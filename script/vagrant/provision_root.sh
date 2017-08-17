#!/bin/bash

#
# Provisioning script for the *privileged* user (root).
#
# Tested on Ubuntu (64 bit)
#

MC_LOCALE_LANG="en_US"
MC_LOCALE_LANG_VARIANT="UTF-8"
MC_TIMEZONE="America/New_York"


# Exit on error
set -e
set -u
set -o errexit

export DEBIAN_FRONTEND=noninteractive

echo "Setting timezone to ${MC_TIMEZONE}..."
ln -sf "/usr/share/zoneinfo/${MC_TIMEZONE}" /etc/localtime
echo -n "$MC_TIMEZONE" > /etc/timezone
dpkg-reconfigure tzdata

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
apt-get -y upgrade

echo "Installing some basic utilities..."
apt-get -y install vim git screen mc zip unzip links htop
