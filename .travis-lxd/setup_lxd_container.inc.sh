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

if [[ $(sudo $LXC_BIN list | grep $MC_LXD_CONTAINER | wc -l) -ge 1 ]]; then
    echo "Destroying old container..."
    sudo $LXC_BIN delete --force $MC_LXD_CONTAINER
fi

echo "Launching container..."
sudo $LXC_BIN launch $MC_LXD_IMAGE $MC_LXD_CONTAINER --profile "$LXD_PROFILE"

# https://github.com/lxc/lxd/issues/3700#issuecomment-323903679
while :; do
    sudo $LXC_BIN exec $MC_LXD_CONTAINER -- getent passwd ubuntu && break
    echo "Waiting for 'ubuntu' user to appear..."
    sleep 1
done

# https://github.com/lxc/lxd/issues/3804#issuecomment-329998197
while :; do
    sudo $LXC_BIN file pull $MC_LXD_CONTAINER/etc/resolv.conf - | grep -q nameserver && break
    echo "Waiting for nameservers to appear in /etc/resolv.conf..."
    sleep 1
done

echo "Testing network..."
sudo $LXC_BIN exec mediacloud-travis -- ping github.com -c 2

export MC_LXD_USER_HOME=/home/$MC_LXD_USER/
export MC_LXD_MEDIACLOUD_ROOT=$MC_LXD_USER_HOME/mediacloud/

echo "Creating test user on container..."
sudo $LXC_BIN exec $MC_LXD_CONTAINER -- /bin/bash -c "useradd -ms /bin/bash $MC_LXD_USER" || echo "User already exists?"
echo "$MC_LXD_USER ALL=(ALL) NOPASSWD:ALL" | sudo $LXC_BIN exec $MC_LXD_CONTAINER -- /bin/bash -c "tee -a /etc/sudoers"

echo "Installing some tools..."
sudo $LXC_BIN exec $MC_LXD_CONTAINER -- /bin/bash -c "apt-get -y update"
sudo $LXC_BIN exec $MC_LXD_CONTAINER -- /bin/bash -c "apt-get -y --no-install-recommends install build-essential file python python-dev python-pip python-setuptools"
sudo $LXC_BIN exec $MC_LXD_CONTAINER -- /bin/bash -c "pip install --upgrade pip"

# Otherwise fails with:
#
#     ERROR! Unexpected Exception, this is probably a bug:
#     (cryptography 1.2.3 (/usr/lib/python3/dist-packages),
#     Requirement.parse('cryptography>=1.5'), {'paramiko'})
#
echo "Upgrading pyOpenSSL..."
sudo $LXC_BIN exec $MC_LXD_CONTAINER -- /bin/bash -c "apt-get --auto-remove --yes remove python-openssl"
sudo $LXC_BIN exec $MC_LXD_CONTAINER -- /bin/bash -c "pip install --upgrade pyOpenSSL"

echo "Installing Ansible and ansible-lint..."
sudo $LXC_BIN exec $MC_LXD_CONTAINER -- /bin/bash -c "pip install --upgrade ansible"
sudo $LXC_BIN exec $MC_LXD_CONTAINER -- /bin/bash -c "pip install --upgrade ansible-lint"

# travis.yml won't do it to Travis runs will waste time reinstalling it again and again
echo "Installing Apache to container..."
sudo $LXC_BIN exec $MC_LXD_CONTAINER -- /bin/bash -c "apt-get -y --no-install-recommends install apache2 libapache2-mod-fcgid"
