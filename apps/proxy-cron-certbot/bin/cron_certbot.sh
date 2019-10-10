#!/bin/bash

set -u
set -e

# Make sure credentials are set
source /opt/mediacloud/bin/credentials.inc.sh

# If no certificate exists at all, generate it straight away without waiting
# for Cron to get around to doing it
if [ ! -f /etc/letsencrypt/live/mediacloud.org/privkey.pem ]; then
	echo "No certificate, generating one straight away..."
	/opt/mediacloud/bin/renew_le_certs.sh
fi

# Run Cron wrapper script from cron-base
exec /cron.sh
