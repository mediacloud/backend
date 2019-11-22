#!/bin/bash

set -e

if [ -z "$MC_MAIL_POSTFIX_FQDN" ]; then
    echo "MC_MAIL_POSTFIX_FQDN (fully qualified domain to use for sending email) is not set."
    exit 1
fi

set -u

# Set up rsyslog for logging
source /rsyslog.inc.sh

# Configure Postfix
postconf -e hostname="${MC_MAIL_POSTFIX_FQDN}"
postconf -e myhostname="${MC_MAIL_POSTFIX_FQDN}"

# Set the right permissions in the data volume
chown -R postfix:postfix /var/lib/postfix/

# Start Postfix
exec /usr/lib/postfix/sbin/master -c /etc/postfix -d
