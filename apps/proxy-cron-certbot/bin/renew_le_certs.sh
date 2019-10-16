#!/bin/bash

set -u
set -e

# Make sure credentials are set
source /opt/mediacloud/bin/credentials.inc.sh

# Write credentials
rm -f /var/tmp/cloudflare.ini
touch /var/tmp/cloudflare.ini
echo "dns_cloudflare_email = \"${MC_PROXY_CERTBOT_CLOUDFLARE_EMAIL}\"" >> /var/tmp/cloudflare.ini
echo "dns_cloudflare_api_key = \"${MC_PROXY_CERTBOT_CLOUDFLARE_GLOBAL_API_KEY}\"" >> /var/tmp/cloudflare.ini

# Try to renew certificates
certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /var/tmp/cloudflare.ini \
    -d "${MC_PROXY_CERTBOT_DOMAIN},*.${MC_PROXY_CERTBOT_DOMAIN}" \
    --preferred-challenges dns-01 \
    --agree-tos \
    -m "${MC_PROXY_CERTBOT_LETSENCRYPT_EMAIL}" \
    -n

# Update certificate for nginx
cat \
    "/etc/letsencrypt/live/${MC_PROXY_CERTBOT_DOMAIN}/privkey.pem" \
    "/etc/letsencrypt/live/${MC_PROXY_CERTBOT_DOMAIN}/fullchain.pem" \
    > "/etc/letsencrypt/live/${MC_PROXY_CERTBOT_DOMAIN}/ssl.pem"
