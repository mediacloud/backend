#!/bin/bash

set -u
set -e

source ./.travis-lxd/config.inc.sh

echo "Setting up LXD..."
source ./.travis-lxd/setup_lxd.inc.sh

echo "Importing LXD image..."
MC_LXD_IMAGE_PROVISIONED_NAME="mediacloud-travis-lxd"
sudo lxc image import "$MC_LXD_IMAGE_PROVISIONED_CACHE_PATH" --alias "$MC_LXD_IMAGE_PROVISIONED_NAME"

echo "Setting up LXD container..."
MC_LXD_IMAGE="$MC_LXD_IMAGE_PROVISIONED_NAME"   # Set up LXD with pre-provisioned Media Cloud image
source ./.travis-lxd/setup_lxd_container.inc.sh

echo "Copying and chowning repository to container..."
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "mkdir -p $MC_LXD_MEDIACLOUD_ROOT"
find . | cpio -o | sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "cd $MC_LXD_MEDIACLOUD_ROOT; cpio -i -d"
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "chown -R $MC_LXD_USER:$MC_LXD_USER $MC_LXD_MEDIACLOUD_ROOT"

# Travis's own scripts might have undefined variables or errors
set +u
set +e
