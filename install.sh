#!/bin/bash

set -u
set -o errexit

if [ `getconf LONG_BIT` != '64' ]; then
   echo "Install failed, you must have a 64 bit OS."
   exit 1
fi

echo "Pulling submodules..."    # in case user forgot to do it
git submodule update --init --recursive

echo "Installing Ansible..."
sudo apt-get -y install python3-pip python3-setuptools
sudo pip3 install --upgrade urllib3[secure]
sudo pip3 install --upgrade pip
sudo pip3 install --upgrade ansible

echo "Setting up Docker..."
cd provision/
ansible-playbook --inventory="localhost," --connection=local --tags docker setup.yml

# FIXME
echo "Pulling images..."
sudo pip3 install --upgrade PyYAML
./dev/pull.py
