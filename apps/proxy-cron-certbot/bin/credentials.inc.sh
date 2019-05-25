set +u

if [ -z "$MC_PROXY_CERTBOT_DOMAIN" ]; then
    echo "MC_PROXY_CERTBOT_DOMAIN (top-level domain to issue the certificate for) is not set."
    exit 1
fi

if [ -z "$MC_PROXY_CERTBOT_LETSENCRYPT_EMAIL" ]; then
    echo "MC_PROXY_CERTBOT_LETSENCRYPT_EMAIL (email for Let's Encrypt's notifications) is not set."
    exit 1
fi

if [ -z "$MC_PROXY_CERTBOT_CLOUDFLARE_EMAIL" ]; then
    echo "MC_PROXY_CERTBOT_CLOUDFLARE_EMAIL (CloudFlare account email) is not set."
    exit 1
fi

if [ -z "$MC_PROXY_CERTBOT_CLOUDFLARE_GLOBAL_API_KEY" ]; then
    echo "MC_PROXY_CERTBOT_CLOUDFLARE_GLOBAL_API_KEY (CloudFlare account global API key) is not set."
    exit 1
fi

set -u
