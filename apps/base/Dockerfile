#
# Base OS image
#
# Build:
#
#     docker build -t mediacloud-base .
#

# https://hub.docker.com/_/ubuntu?tab=tags&page=1
FROM ubuntu:focal-20210713

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US \
    #
    # It is likely that we'll run a Python script somewhere in the final app. By
    # default, Python will buffer lines print()ed to STDOUT / STDERR, and they
    # might end up in container's log after a delay and with a wrong timestamp
    # (e.g. log messages). So, disable such buffering altogether to all containers
    # by default.
    PYTHONUNBUFFERED=1 \
    #
    # Don't create .pyc files
    PYTHONDONTWRITEBYTECODE=1

# Use mirror closest to us
COPY conf/apt/sources.list /etc/apt/

# Upgrade packages
RUN \
    apt-get -y update && \
    apt-get -y upgrade && \
    apt-get -y autoremove && \
    apt-get -y clean

# Install system packages that the base image is missing in a "magic" order
RUN \
    apt-get -y --no-install-recommends install ca-certificates && \
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
        # "mail" utility which uses sendmail (provided by msmtp-mta) internally;
        # some tools like munin-cron use "mail" to send emails
        bsd-mailx \
        curl \
        htop \
        # apt-key
        gnupg \
        # "ip" and similar utilities
        iproute2 \
        # Pinging other containers from within Compose environment
        iputils-ping \
        # Provides "sendmail" utility which relays email through
        # "mail-postfix-server" app
        msmtp \
        msmtp-mta \
        # Provides killall among other utilities
        psmisc \
        less \
        locales \
        # Waiting for some port to open
        netcat \
        # Some packages insist on logging to syslog
        rsyslog \
        # Timezone data, used by many packages
        tzdata \
        # Basic editor for files in container while debugging
        # (full vim is too big)
        vim-tiny \
    && \
    true

# Symlink vim
RUN ln -s /usr/bin/vim.tiny /usr/bin/vim

# Copy rsyslog configuration
COPY conf/rsyslog.conf /etc/
COPY bin/rsyslog.inc.sh /

# Copy helper scripts
COPY bin/container_memory_limit.sh bin/container_cpu_limit.sh bin/dl_to_stdout.sh /

# Copy MSMTP configuration
COPY conf/msmtprc conf/msmtp-aliases /etc/

# Both "sendmail" and "mail" utilities are important as they're used by various
# apps (e.g. munin-cron) to send us important email, and those apps aren't
# particularly vocal when they're unable to send email. So, for extra paranoia,
# verify that both utilities point to correct symlinks here.
RUN \
    if [ "$(readlink -- "/usr/sbin/sendmail")" != "../bin/msmtp" ]; then \
        echo "sendmail is not symlinked to msmtp, sending email won't work." && \
        exit 1; \
    fi; \
    if [ "$(readlink -- "/usr/bin/mail")" != "/etc/alternatives/mail" ]; then \
        echo "mail is not symlinked to /etc/alternatives/mail, sending email won't work." && \
        exit 1; \
    fi; \
    if [ "$(readlink -- "/etc/alternatives/mail")" != "/usr/bin/bsd-mailx" ]; then \
        echo "mail is not symlinked to /etc/alternatives/mail, sending email won't work." && \
        exit 1; \
    fi; \
    true

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
    echo "* soft nofile 65536" >> /etc/security/limits.conf && \
    echo "* hard nofile 65536" >> /etc/security/limits.conf && \
    true
