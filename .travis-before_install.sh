#!/bin/bash

set -u
set -e

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

echo "Initializing LXD..."
sudo lxd init --auto --storage-backend=dir

echo "Setting up LXD's network..."
sudo lxc network create testbr0
sudo lxc network attach-profile testbr0 default eth0

echo "Removing linuxcontainers.org repo..."
sudo lxc remote remove images || echo "Not here?"

echo "Updating LXD profile..."
sudo lxc profile copy default travis
sudo lxc profile set travis security.privileged true

echo "Launching container..."
sudo lxc launch $MC_LXD_IMAGE $MC_LXD_CONTAINER --profile travis

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

echo "Copying and chowning repository to container..."
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "mkdir -p $MC_LXD_MEDIACLOUD_ROOT"
find . | cpio -o | sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "cd $MC_LXD_MEDIACLOUD_ROOT; cpio -i -d"
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "chown -R $MC_LXD_USER:$MC_LXD_USER $MC_LXD_MEDIACLOUD_ROOT"

echo "Installing some tools..."
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "apt-get -y update"
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "apt-get -y install build-essential file python python-dev python-pip python-setuptools"
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "pip install --upgrade pip"

echo "Installing Ansible and ansible-lint..."
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "pip install --upgrade ansible"
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "pip install --upgrade ansible-lint"

# Travis's own scripts might have undefined variables or errors
set +u
set +e
