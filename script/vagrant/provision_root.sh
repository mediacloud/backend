#!/bin/bash

#
# Provisioning script for the *privileged* user (root).
#
# Tested on "precise64" (Ubuntu 12.04, 64 bit; http://files.vagrantup.com/precise64.box)
#

MC_HOSTNAME="mediacloud"
MC_DOMAINNAME="local"
MC_LOCALE_LANG="en_US"
MC_LOCALE_LANG_VARIANT="UTF-8"

echo "Setting hostname to $MC_HOSTNAME.$MC_DOMAINNAME..."
echo -n $MC_HOSTNAME.$MC_DOMAINNAME > /etc/hostname
service hostname restart
echo "127.0.0.1 $MC_HOSTNAME $MC_HOSTNAME.$MC_DOMAINNAME" >> /etc/hosts

echo "Setting default locale (or else Perl's test locale.t will fail)..."
locale-gen $MC_LOCALE_LANG
locale-gen $MC_LOCALE_LANG.$MC_LOCALE_LANG_VARIANT
update-locale LANG=$MC_LOCALE_LANG.$MC_LOCALE_LANG_VARIANT LANGUAGE=$MC_LOCALE_LANG
dpkg-reconfigure locales
source /etc/profile

echo "Installing GRUB so that APT doesn't complain..."
grub-install /dev/sda
update-grub

echo "Upgrading packages with APT..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade

echo "Installing some basic utilities..."
apt-get -y install vim git screen mc zip unzip links
