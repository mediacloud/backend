#!/bin/bash

set -u
set -o errexit

if [ "$EUID" -eq 0 ]; then
    echo "Please run this script from the user from which you intend to run Media Cloud services."
    exit 1
fi

if [ `uname` == 'Darwin' ]; then
    # Mac OS X -- nothing to do
    :
else

    PAM_COMMON_SESSION_FILE=/etc/pam.d/common-session
    if [ ! -f "$PAM_COMMON_SESSION_FILE" ]; then
        echo "PAM common-session file does not exist at $PAM_COMMON_SESSION_FILE"
        exit 1
    fi
    if ! grep -q "pam_limits.so" "$PAM_COMMON_SESSION_FILE"; then
        echo "Adding pam_limits.so to PAM common-session file $PAM_COMMON_SESSION_FILE..."

        sudo tee -a "$PAM_COMMON_SESSION_FILE" <<EOF

# Enforce Media Cloud limits
session required pam_limits.so

EOF
    fi

    PAM_SUDO_FILE=/etc/pam.d/sudo
    if [ ! -f "$PAM_SUDO_FILE" ]; then
        echo "PAM sudo file does not exist at $PAM_SUDO_FILE"
        exit 1
    fi
    if ! grep -q "pam_limits.so" "$PAM_SUDO_FILE"; then
        echo "Adding pam_limits.so to PAM sudo file $PAM_SUDO_FILE..."

        sudo tee -a "$PAM_SUDO_FILE" <<EOF

# Enforce Media Cloud limits
session required pam_limits.so

EOF
    fi

    SYSCTL_FILE=/etc/sysctl.d/50-mediacloud.conf
    sudo tee "$SYSCTL_FILE" <<EOF
#
# Media Cloud kernel parameters
#

# We connect to PgBouncer often, so it might run out of available connections
# without TIME_WAIT socket reuse (http://dba.stackexchange.com/a/59709)
net.ipv4.tcp_tw_reuse=1

EOF

    echo "Rereading sysctl settings..."
    sudo service procps start

    MEDIACLOUD_ULIMIT_VIRTUAL_MEMORY=33554432   # Each process is limited up to ~34 GB of memory
    MEDIACLOUD_ULIMIT_OPEN_FILES=65536

    MEDIACLOUD_USER=`id -un`
    echo "Setting required kernel parameters via limits.conf for user '$MEDIACLOUD_USER'..."

    LIMITS_FILE=/etc/security/limits.d/50-mediacloud.conf
    sudo tee "$LIMITS_FILE" <<EOF
#
# Media Cloud limits
#

# Each process is limited up to ~34 GB of memory
$MEDIACLOUD_USER      hard    as            $MEDIACLOUD_ULIMIT_VIRTUAL_MEMORY

# Increase the max. open files limit
$MEDIACLOUD_USER      soft    nofile        $MEDIACLOUD_ULIMIT_OPEN_FILES
$MEDIACLOUD_USER      hard    nofile        $MEDIACLOUD_ULIMIT_OPEN_FILES
EOF

    echo "Done setting required kernel parameters via limits.conf."
    
    echo "Setting required kernel parameters directly via ulimit..."
    ulimit -v $MEDIACLOUD_ULIMIT_VIRTUAL_MEMORY
    ulimit -n $MEDIACLOUD_ULIMIT_OPEN_FILES
    echo "Setting required kernel parameters directly via ulimit."

    echo "Current ulimit values:\n`ulimit -a`"

fi
