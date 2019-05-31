#
# Postfix server
#

FROM dockermediacloud/base:latest

# FIXME keep in sync with main-opendkim-server?
ENV MC_MAIL_POSTFIX_MAILNAME "mail.mediacloud.org"

# Install packages
RUN \
    #
    # Remove ssmtp (not compatible with Postfix)
    apt-get -y remove ssmtp && \
    #
    # Install Postfix
    apt-get -y --no-install-recommends install postfix && \
    true

# Configure Postfix
RUN \
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

# Postfix data directory
VOLUME /var/lib/postfix/

# Local mail
VOLUME /var/lib/mail/

# Mail queue
VOLUME /var/spool/postfix/

# SMTP port
EXPOSE 25

# Start OpenDKIM
COPY bin/postfix.sh /

CMD ["/postfix.sh"]
