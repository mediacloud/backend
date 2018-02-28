#!/bin/bash
#
# Set up LXD container that will be fetched by Travis for testing.
#
# Travis could use vanilla Ubuntu 16.04 LXD image that it could fetch and run
# Ansible provisioning script on top of it. However, it takes a lot of time to
# install all the system / Perl / Python dependencies and there isn't much time
# left to run the actual tests.
#
# So, using this script, we pre-create the Ubuntu LXD container ourselves by
# fetching a fresh Ubuntu base image, running limited Ansible provisioning
# playbook (which installs all the heavy dependencies), save the container as
# an image and upload it to S3.
#
# Later, every Travis run will fetch the pre-provisioned image from S3, rerun
# the full Ansible playbook on it, and then run the test suite.
#
# Works on Ubuntu 16.04 or above only (because macOS doesn't support LXD).
#
# Usage:
#
# 1) Install AWS CLI tools:
#
#    pip install awscli
#
# 2) Configure AWS CLI tools with your AWS credentials:
#
#    aws configure
#
# 3) Run this script:
#
#    cd .travis-lxd/
#    ./setup_travis_lxd_image.sh
#
# 4) Copy and run the "aws s3 cp ..." command as instructed by the script.
#
# 5) Update MC_LXD_IMAGE_PROVISIONED_URL in ./.travis-lxd/config.inc.sh as instructed by the script.
#

# ---

set -u
set -e

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/config.inc.sh"

source $PWD/config.inc.sh
MC_LXD_IMAGE=MC_LXD_IMAGE_UBUNTU_BASE   # Set up LXD with Ubuntu's base image

echo "Setting up LXD..."
source $PWD/setup_lxd.inc.sh

echo "Setting up LXD container..."
source $PWD/setup_lxd_container.inc.sh

echo "Copying Ansible configuration to container..."
MC_LXD_USER_HOME=/home/$MC_LXD_USER/
MC_LXD_MEDIACLOUD_ROOT=$MC_LXD_USER_HOME/mediacloud/
sudo lxc exec $MC_LXD_CONTAINER -- mkdir -p $MC_LXD_MEDIACLOUD_ROOT/ansible/
sudo lxc file push --recursive $PWD/../ansible/* $MC_LXD_CONTAINER/$MC_LXD_MEDIACLOUD_ROOT/ansible/
sudo lxc exec $MC_LXD_CONTAINER -- chown -R $MC_LXD_USER:$MC_LXD_USER $MC_LXD_MEDIACLOUD_ROOT

echo "Provisioning container with Ansible..."
sudo lxc exec $MC_LXD_CONTAINER -- sudo -H -u $MC_LXD_USER /bin/bash -c \
    "cd $MC_LXD_MEDIACLOUD_ROOT/ansible/;
    ansible-playbook --inventory='localhost,' --connection=local -vvv travis.yml"

echo "Cleaning up container..."
sudo lxc exec $MC_LXD_CONTAINER -- rm -rf $MC_LXD_MEDIACLOUD_ROOT
sudo lxc exec $MC_LXD_CONTAINER -- rm -rf $MC_LXD_USER_HOME/.cache/
sudo lxc exec $MC_LXD_CONTAINER -- rm -rf $MC_LXD_USER_HOME/.cpanm/
sudo lxc exec $MC_LXD_CONTAINER -- rm -rf /root/.cache/
sudo lxc exec $MC_LXD_CONTAINER -- apt-get -y clean
sudo lxc exec $MC_LXD_CONTAINER -- apt-get -y autoremove

echo "Stopping container..."
sudo lxc stop mediacloud-travis

MC_LXD_ALIAS="$MC_LXD_CONTAINER-`date +%Y%m%d`"

echo "Publishing image as '$MC_LXD_ALIAS'..."
sudo lxc publish $MC_LXD_CONTAINER --alias $MC_LXD_ALIAS --public --verbose

echo "Exporting image '$MC_LXD_ALIAS'..."
sudo lxc image export $MC_LXD_ALIAS $MC_LXD_ALIAS

S3_BUCKET_NAME="mediacloud-travis-lxd-images"
S3_DIRECTORY_NAME="travis-lxd-images"
echo "Done!"
echo
echo "Now upload the newly created image to S3:"
echo
echo "    aws s3 cp --content-type application/gzip $MC_LXD_ALIAS.tar.gz s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/"
echo
echo "and update MC_LXD_IMAGE_PROVISIONED_URL in ./.travis-lxd/config.inc.sh:"
echo
echo "    MC_LXD_IMAGE_PROVISIONED_URL=https://s3.amazonaws.com/$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$MC_LXD_ALIAS.tar.gz"
echo
