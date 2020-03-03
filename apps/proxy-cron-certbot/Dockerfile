#
# Cron job that renews Let's Encrypt certificate
# (have a look at credentials.inc.sh for configuration options)
#

FROM dockermediacloud/cron-base:latest

# Install packages
RUN \
    #
    # Install Certbot
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 7BF576066ADA65728FC7E70A8C47BE8E75BCA694 && \
    echo "deb http://ppa.launchpad.net/certbot/certbot/ubuntu xenial main" > /etc/apt/sources.list.d/certbot.list && \
    apt-get -y update && \
    apt-get -y --no-install-recommends install certbot python3-certbot-dns-cloudflare && \
    #
    # Make sure Certbot appears to be working
    certbot --version && \
    #
    true

# Remove preinstalled Cron job
RUN rm /etc/cron.d/certbot

# Copy Cron script
COPY bin /opt/mediacloud/bin
ENV PATH="/opt/mediacloud/bin:${PATH}"

# Add Cron job
ADD crontab /etc/cron.d/certbot_renew
RUN chmod 0644 /etc/cron.d/certbot_renew

# Volume for issued certificates
# (used by proxy_httpd)
VOLUME /etc/letsencrypt/

# No USER because writes to /etc/letsencrypt/

CMD ["cron_certbot.sh"]
