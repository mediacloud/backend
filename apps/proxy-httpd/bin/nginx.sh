#!/bin/bash

set -u
set -e

# Wait for proxy_cron_certbot to generate us a SSL certificate
while true; do
    echo "Waiting for Let's Encrypt certificate to appear..."
    if [ -e /etc/letsencrypt/live/testmediacloud.ml/ssl.pem ]; then
        break
    else
        sleep 1
    fi
done

# Start nginx
echo "Starting nginx..."
exec nginx
