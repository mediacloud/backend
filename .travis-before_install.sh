#!/bin/bash

set -u
set -e

echo "Setting up LXD container..."
source ./.travis-lxd/setup_lxd_base.inc.sh

echo "Copying and chowning repository to container..."
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "mkdir -p $MC_LXD_MEDIACLOUD_ROOT"
find . | cpio -o | sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "cd $MC_LXD_MEDIACLOUD_ROOT; cpio -i -d"
sudo lxc exec $MC_LXD_CONTAINER -- /bin/bash -c "chown -R $MC_LXD_USER:$MC_LXD_USER $MC_LXD_MEDIACLOUD_ROOT"

# Travis's own scripts might have undefined variables or errors
set +u
set +e
