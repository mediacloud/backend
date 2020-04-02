#!/bin/bash
#
# Free up disk space on GitHub Actions instance before running anything else
#

set -u
set -e

if [ -z ${GITHUB_ACTIONS+x} ]; then
    echo "Please run this script on GitHub Actions instance only!"
    exit 1
fi

echo
echo "Disk space before clean up:"
df -h

echo
echo "Disabling swap..."
sudo swapoff -a

echo "Removing swapfile..."
sudo rm -f /swapfile

echo "Cleaning APT cache..."
sudo apt clean

echo "Removing docker images..."
docker rmi $(docker image ls -aq)

echo
echo "Disk space after clean up:"
df -h
