#!/bin/bash

#
# Provisioning script for the *privileged* user (root).
#
# Tested on Ubuntu (64 bit)
#


# Exit on error
set -e
set -u
set -o errexit

export DEBIAN_FRONTEND=noninteractive

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
