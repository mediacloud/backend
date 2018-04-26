#
# Base OS image
#
# Build:
#
#     docker build -t mediacloud-base .
#

FROM ubuntu:xenial

ENV DEBIAN_FRONTEND noninteractive
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US

# Upgrade packages
RUN \
    apt-get -y update && \
    apt-get -y upgrade && \
    apt-get -y autoremove && \
    apt-get -y clean

# Install system packages that the base image is missing in a "magic" order
RUN \
    apt-get -y --no-install-recommends install apt-utils && \
    apt-get -y --no-install-recommends install apt-transport-https && \
    apt-get -y --no-install-recommends install acl && \
    apt-get -y --no-install-recommends install sudo && \
    apt-get -y --no-install-recommends install file && \
    true

# Install common packages
RUN \
    apt-get -y --no-install-recommends install \
        # Quicker container debugging
        bash-completion \
        # Some of the packages might want to use SSL
        ca-certificates \
        curl \
        htop \
        less \
        locales \
        # Waiting for some port to open
        netcat \
        # Some packages insist on logging to syslog
        rsyslog \
        # add-apt-repository
        software-properties-common \
        tzdata \
        # Editing stuff while debugging
        vim \
    && \
    true

# Copy rsyslog configuration
COPY conf/rsyslog.conf /etc/
COPY bin/rsyslog.inc.sh /

# Generate and set locale
RUN \
    locale-gen en_US en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LANGUAGE=en_US && \
    true

# Set timezone
RUN \
    echo "America/New_York" > /etc/timezone && \
    rm /etc/localtime && \
    ln -s /usr/share/zoneinfo/America/New_York /etc/localtime && \
    dpkg-reconfigure tzdata && \
    true

# Set PAM limits
RUN \
    echo "session required pam_limits.so" >> /etc/pam.d/common-session && \
    echo "session required pam_limits.so" >> /etc/pam.d/sudo && \
    echo "root soft nofile 65536" >> /etc/security/limits.conf && \
    echo "root hard nofile 65536" >> /etc/security/limits.conf && \
    true

# Set Vim as default system-wide editor
RUN update-alternatives --set editor /usr/bin/vim.basic
