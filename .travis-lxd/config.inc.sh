#
# Travis LXD container configuration
#

# LXD image to pull with pre-installed Media Cloud dependencies
MC_LXD_IMAGE=ubuntu:xenial

# Container name
MC_LXD_CONTAINER=mediacloud-travis

# Unprivileged user on container (which can sudo)
MC_LXD_USER=ubuntu
