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

# Don't touch swap as we might not be able to fit all the things that we run in RAM

echo
echo "Cleaning APT cache..."
sudo apt clean

echo "Removing some directories..."
sudo rm -rf /usr/local/lib/android/
sudo rm -rf /usr/local/lib/node_modules/
sudo rm -rf /usr/local/share/chromium/

echo "Removing docker images..."
docker rmi $(docker image ls -aq)

echo
echo "Disk space after clean up:"
df -h
