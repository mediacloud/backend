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

    MEDIACLOUD_USER=`id -un`
    echo "Setting required kernel parameters via limits.conf for user '$MEDIACLOUD_USER'..."

    LIMITS_FILE=/etc/security/limits.d/50-mediacloud.conf
    sudo tee "$LIMITS_FILE" <<EOF
#
# Media Cloud limits
#

# Each process is limited up to ~34 GB of memory
$MEDIACLOUD_USER      hard    as            33554432

# Increase the max. open files limit
$MEDIACLOUD_USER      soft    nofile        65536
$MEDIACLOUD_USER      hard    nofile        65536
EOF

    echo "Done setting required kernel parameters via limits.conf."
    echo "Please relogin to the user '$MEDIACLOUD_USER' for the limits to be applied."

fi
