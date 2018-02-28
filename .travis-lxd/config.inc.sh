#
# Travis LXD container configuration
#

# URL of LXD image with pre-provisioned Media Cloud dependencies
MC_LXD_IMAGE_PROVISIONED_URL=https://s3.amazonaws.com/mediacloud-travis-lxd-images/travis-lxd-images/mediacloud-travis-20180228.tar.gz

# LXD image with base Ubuntu
MC_LXD_IMAGE_UBUNTU_BASE=ubuntu:xenial

# Container name
MC_LXD_CONTAINER=mediacloud-travis

# Unprivileged user on container (which can sudo)
MC_LXD_USER=ubuntu
