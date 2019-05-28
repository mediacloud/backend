#!/bin/bash

set -e

if [ -z "$MC_MAIL_POSTFIX_DOMAIN" ]; then
    echo "MC_MAIL_POSTFIX_DOMAIN (top-level domain to use for sending email) is not set."
    exit 1
fi

if [ -z "$MC_MAIL_POSTFIX_HOSTNAME" ]; then
    echo "MC_MAIL_POSTFIX_HOSTNAME (mail server hostname) is not set."
    exit 1
fi

set -u

# Set up rsyslog for logging
source /rsyslog.inc.sh

# Configure Postfix
postconf -e hostname="${MC_MAIL_POSTFIX_HOSTNAME}.${MC_MAIL_POSTFIX_DOMAIN}"

# Start Postfix
exec /usr/lib/postfix/sbin/master -c /etc/postfix -d
