#
# Travis LXD container configuration
#

# URL of LXD image with pre-provisioned Media Cloud dependencies
# (use ./.travis-lxd/setup_travis_lxd_image.sh) to create a new one)
MC_LXD_IMAGE_PROVISIONED_URL=https://s3.amazonaws.com/mediacloud-travis-lxd-images/travis-lxd-images/mediacloud-travis-20190115.tar.gz

# LXD image with base Ubuntu
MC_LXD_IMAGE_UBUNTU_BASE=ubuntu:xenial

# Container name
MC_LXD_CONTAINER=mediacloud-travis

# Unprivileged user on container (which can sudo)
MC_LXD_USER=ubuntu

# Path to LXC binary
# (we install LXD from Snap but an outdated lxd-tools might still be around)
LXC_BIN=/snap/bin/lxc
