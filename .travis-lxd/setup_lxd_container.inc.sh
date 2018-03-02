#
# Set up LXD container
#

set -u
set -e

if [ -z "$MC_LXD_IMAGE" ]; then
    echo "Please load the configuration first:"
    echo
    echo "    source ./.travis-lxd/config.inc.sh"
    echo
    echo "and set MC_LXD_IMAGE to the image that you want to set up, e.g.:"
    echo
    echo "    MC_LXD_IMAGE=$MC_LXD_IMAGE_UBUNTU_BASE"
    echo
    exit 1
fi

if [ -z "$LXD_PROFILE" ]; then
    echo "Please run LXD setup first:"
    echo
    echo "    source ./.travis-lxd/setup_lxd.inc.sh"
    echo
    exit 1
fi

if [[ $(sudo lxc list | grep $MC_LXD_CONTAINER | wc -l) -ge 1 ]]; then
    echo "Destroying old container..."
    sudo lxc delete --force $MC_LXD_CONTAINER
fi

echo "Launching container..."
sudo lxc launch $MC_LXD_IMAGE $MC_LXD_CONTAINER --profile "$LXD_PROFILE"

# User list, network, ... doesn't get loaded right away after "lxc launch"
# (FIXME maybe do some sort of polling here)
echo "Waiting for everything to get launched..."
sleep 10

echo "Printing LXD image list..."
sudo lxc image list

echo "Printing information about every LXD image..."
sudo lxc image list --format csv | xargs -L1 echo | awk -F  "," '{ print $2 }' | xargs sudo lxc image info

echo "Testing network..."
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
