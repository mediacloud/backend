#
# Postfix server
#

FROM dockermediacloud/base:latest

# Install packages
RUN \
    #
    # Remove ssmtp (not compatible with Postfix)
    apt-get -y remove ssmtp && \
    #
    # Install Postfix
    apt-get -y --no-install-recommends install postfix && \
    #
    # Create directories for storing Postfix's data and mail queue && \
    mkdir -p /var/lib/postfix/data/ && \
    mv /var/spool/postfix/ /var/lib/postfix/queue/ && \
    chown -R postfix:postfix /var/lib/postfix/ && \
    true

# Configure Postfix
RUN \
    #
    # Set custom data and queue directories
    postconf -e data_directory=/var/lib/postfix/data/ && \
    postconf -e queue_directory=/var/lib/postfix/queue/ && \
    #
    # Configure OpenDKIM
    postconf -e milter_protocol=2 && \
    postconf -e milter_default_action=accept && \
    postconf -e smtpd_milters=inet:mail-opendkim-server:12301 && \
    postconf -e non_smtpd_milters=inet:mail-opendkim-server:12301 && \
    #
    # Relay all emails with a non-localhost destination
    postconf -e mydestination=localhost && \
    #
    # Accept email from Docker network
    postconf -e mynetworks=0.0.0.0/0 && \
    #
    # Don't require TLS as local clients are trusted
    postconf -e smtp_tls_security_level=may && \
    postconf -e smtpd_tls_security_level=none && \
    true

# Postfix data and queue directory
VOLUME /var/lib/postfix/

# SMTP port
EXPOSE 25

# Copy wrapper script
COPY bin/postfix.sh /

# No USER because daemon will demote itself to "postfix" user itself

CMD ["/postfix.sh"]
