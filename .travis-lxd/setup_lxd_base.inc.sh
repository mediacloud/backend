#!/bin/bash
#
# Set up LXD base container
#

set -u
set -e

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/config.inc.sh"

echo "Updating package list..."
sudo apt-get -y update

echo "Removing old LXD..."
sudo apt-get -y remove lxd
sudo apt-get -y autoremove

echo "Installing Snap..."
sudo apt-get -y install snapd
echo "PATH=/snap/bin:$PATH" | sudo tee -a /etc/environment
export PATH=/snap/bin:$PATH

echo "Installing LXD from Snap (APT's version is too old)..."
sudo snap install lxd

echo "Waiting for LXD to start..."
sudo snap start lxd
sudo lxd waitready

echo "Removing linuxcontainers.org repo..."
sudo lxc remote remove images || echo "Not here?"

if [ ! -f /var/lib/lxd/lxd.db ]; then
    echo "Initializing LXD..."
    sudo lxd init --auto --storage-backend=dir
fi

LXD_BRIDGE_INTERFACE=testbr0
if [[ $(sudo lxc network list | grep $LXD_BRIDGE_INTERFACE | wc -l) -eq 0 ]]; then
    echo "Setting up LXD networking..."
    sudo lxc network create $LXD_BRIDGE_INTERFACE
    sudo lxc network attach-profile $LXD_BRIDGE_INTERFACE default eth0
fi

LXD_PROFILE=travis
if [[ $(sudo lxc profile list | grep $LXD_PROFILE | wc -l) -eq 0 ]]; then
    echo "Creating LXD profile..."
    sudo lxc profile copy default $LXD_PROFILE
    sudo lxc profile set $LXD_PROFILE security.privileged true
fi

if [[ $(sudo lxc list | grep $MC_LXD_CONTAINER | wc -l) -ge 1 ]]; then
    echo "Destroying old container..."
    sudo lxc delete --force $MC_LXD_CONTAINER
fi

echo "Launching container..."
sudo lxc launch $MC_LXD_IMAGE $MC_LXD_CONTAINER --profile $LXD_PROFILE

echo "Printing LXD image list..."
sudo lxc image list

echo "Printing information about every LXD image..."
sudo lxc image list --format csv | xargs -L1 echo | awk -F  "," '{ print $2 }' | xargs sudo lxc image info

echo "Testing network..."
sleep 5
sudo lxc exec mediacloud-travis -- ping github.com -c 2

export MC_LXD_USER_HOME=/home/$MC_LXD_USER/
export MC_LXD_MEDIACLOUD_ROOT=$MC_LXD_USER_HOME/mediacloud/

echo "Creating test user on container..."
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "useradd -ms /bin/bash $MC_LXD_USER" || echo "User already exists?"
echo "$MC_LXD_USER ALL=(ALL) NOPASSWD:ALL" | sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "tee -a /etc/sudoers"

echo "Installing some tools..."
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "apt-get -y update"
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "apt-get -y --no-install-recommends install build-essential file python python-dev python-pip python-setuptools"
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "pip install --upgrade pip"

echo "Installing Ansible and ansible-lint..."
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "pip install --upgrade ansible"
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "pip install --upgrade ansible-lint"

# travis.yml won't do it to Travis runs will waste time reinstalling it again and again
echo "Installing Apache to container..."
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "apt-get -y --no-install-recommends install apache2 libapache2-mod-fcgid"
