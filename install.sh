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
ansible-playbook --inventory="localhost," --connection=local --tags=docker setup.yml

echo "Installing PyYAML..."
sudo pip3 install --upgrade PyYAML

cat << EOF

Installation is complete!

To pull pre-built app Docker images, run:

    ./dev/pull.py

To run Media Cloud in production, you might want to create docker-compose.yml
(using apps/docker-compose.dist.yml as a template) to fit your needs and start
all the services by running:

    docker-compose up

To start developing Media Cloud, you might want to start individual apps
together with their dependencies using a Docker Compose testing environment
defined in each app's docker-compose.tests.yml.

Please refer to the documentation (docs/) for more information.

EOF
