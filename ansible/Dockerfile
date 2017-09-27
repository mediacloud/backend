#
# Docker configuration to set up a Ubuntu 16.04 image with Media Cloud
# dependencies preinstalled for Travis to pull and use later.
#
# To build and publish, run:
#
#     cd ansible/
#     docker build -t mediacloud-travis .
#     docker tag mediacloud-travis:latest dockermediacloud/mediacloud-travis:<YYYYMMDD>
#     docker push dockermediacloud/mediacloud-travis:<YYYYMMDD>
#     # Update Docker image tag in .travis.yml
#

FROM ubuntu:16.04

ENV DEBIAN_FRONTEND noninteractive

COPY . /mediacloud-ansible/

RUN \
    apt-get -y update && \
    apt-get -y --no-install-recommends install apt-utils && \
    apt-get -y --no-install-recommends install apt-transport-https && \
    apt-get -y --no-install-recommends install sudo && \
    apt-get -y --no-install-recommends install build-essential file python python-dev python-pip python-setuptools && \
    apt-get -y --no-install-recommends install apache2 libapache2-mod-fcgid && \
    apt-get -y clean && \
    \
    pip install --upgrade pip && \
    pip install --upgrade ansible && \
    rm -rf /root/.cache/ && \
    \
    useradd -ms /bin/bash mediacloud && \
    echo 'mediacloud ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99_mediacloud && \
    \
    mkdir /home/mediacloud/mediacloud/ && \
    mv /mediacloud-ansible /home/mediacloud/mediacloud/ansible/ && \
    chown -R mediacloud:mediacloud /home/mediacloud/mediacloud/

USER mediacloud
WORKDIR /home/mediacloud/mediacloud/ansible/

RUN \
    ansible-playbook \
    --inventory="localhost," \
    --connection=local \
    -vvv travis.yml && \
    \
    sudo rm -rf /home/mediacloud/.cache/ && \
    sudo rm -rf /home/mediacloud/.cpanm/ && \
    sudo rm -rf /root/.cache/ && \
    sudo apt-get -y clean

WORKDIR /home/mediacloud

RUN \
    sudo rm -rf /home/mediacloud/mediacloud/
