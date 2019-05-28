#!/bin/bash

set -e

if [ -z "$MC_MAIL_OPENDKIM_DOMAIN" ]; then
    echo "MC_MAIL_OPENDKIM_DOMAIN (top-level domain to use for signing emails) is not set."
    exit 1
fi

if [ -z "$MC_MAIL_OPENDKIM_HOSTNAME" ]; then
    echo "MC_MAIL_OPENDKIM_HOSTNAME (mail server hostname) is not set."
    exit 1
fi

set -u

# (Re)generate dynamic configuration
rm -f /etc/opendkim/KeyTable
echo "${MC_MAIL_OPENDKIM_HOSTNAME}._domainkey.${MC_MAIL_OPENDKIM_DOMAIN} ${MC_MAIL_OPENDKIM_DOMAIN}:${MC_MAIL_OPENDKIM_HOSTNAME}:/etc/opendkim/keys/${MC_MAIL_OPENDKIM_HOSTNAME}.private" \
    > /etc/opendkim/KeyTable
rm -f /etc/opendkim/SigningTable
echo "*@${MC_MAIL_OPENDKIM_DOMAIN} ${MC_MAIL_OPENDKIM_HOSTNAME}._domainkey.${MC_MAIL_OPENDKIM_DOMAIN}" \
    > /etc/opendkim/SigningTable

# Generate keys if those are missing
if [ ! -f "/etc/opendkim/keys/${MC_MAIL_OPENDKIM_HOSTNAME}.private" ]; then
    opendkim-genkey \
        -s "${MC_MAIL_OPENDKIM_HOSTNAME}" \
        -d "${MC_MAIL_OPENDKIM_DOMAIN}" \
        -D /etc/opendkim/keys/
    chown opendkim:opendkim "/etc/opendkim/keys/${MC_MAIL_OPENDKIM_HOSTNAME}.private"
fi

# Print public key before every run
echo
echo "Add the following DNS record to ${MC_MAIL_OPENDKIM_DOMAIN} domain if you haven't already:"
echo
cat "/etc/opendkim/keys/${MC_MAIL_OPENDKIM_HOSTNAME}.txt"
echo

# Set up rsyslog for logging
source /rsyslog.inc.sh

# Start OpenDKIM
exec opendkim \
    -f \
    -v \
    -x /etc/opendkim.conf \
    -u opendkim \
    -P /var/run/opendkim/opendkim.pid \
    -p inet:12301@localhost
