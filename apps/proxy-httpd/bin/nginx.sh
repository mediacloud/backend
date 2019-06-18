#!/bin/bash

set -u
set -e

set +u
if [ -z "$MC_PROXY_HTTPD_AUTH_USERS" ]; then
    echo "MC_PROXY_HTTPD_AUTH_USERS (user credentials for restricted webapps) is not set."
    exit 1
fi
set -u

# Create htpasswd
rm -f /var/lib/mediacloud-htpasswd
touch /var/lib/mediacloud-htpasswd
while IFS=';' read -ra USERS; do
    for USER in "${USERS[@]}"; do

        while IFS=':' read -ra USER_CREDENTIALS; do
            USERNAME="${USER_CREDENTIALS[0]}"
            PASSWORD="${USER_CREDENTIALS[1]}"
            
            htpasswd -bB /var/lib/mediacloud-htpasswd "${USERNAME}" "${PASSWORD}"

        done <<< "$USER"

    done
done <<< "${MC_PROXY_HTTPD_AUTH_USERS}"

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
