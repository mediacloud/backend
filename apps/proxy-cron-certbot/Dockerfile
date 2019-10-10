#
# Cron job that renews Let's Encrypt certificate
# (have a look at credentials.inc.sh for configuration options)
#

FROM dockermediacloud/cron-base:latest

# Install packages
RUN \
    #
    # Install Certbot
    apt-get -y --no-install-recommends install certbot && \
    #
    # Install CloudFlare plugin
    apt-get -y --no-install-recommends install python-pip && \
    pip install certbot-dns-cloudflare && \
    true

# Remove preinstalled Cron job
RUN rm /etc/cron.d/certbot

# Copy Cron script
COPY bin /opt/mediacloud/bin
ENV PATH "/opt/mediacloud/bin:${PATH}"

# Add Cron job
ADD crontab /etc/cron.d/certbot_renew
RUN chmod 0644 /etc/cron.d/certbot_renew

# Volume for issued certificates
# (used by proxy_httpd)
VOLUME /etc/letsencrypt/

# No USER because writes to /etc/letsencrypt/

CMD ["cron_certbot.sh"]
