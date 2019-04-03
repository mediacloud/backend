#
# Postfix server
#

FROM dockermediacloud/mediacloud-base:latest

# FIXME keep in sync with main-opendkim-server?
ENV MC_MAIL_POSTFIX_MAILNAME "mail.mediacloud.org"
ENV MC_MAIL_POSTFIX_OPENDKIM_HOST "mediacloud_mail_opendkim_server"

# Configure Postfix package
RUN \
    #
    # Configure Postfix as Internet Site
    echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections && \
    #
    # Set Postfix hostname
    echo "postfix postfix/mailname string ${MC_MAIL_POSTFIX_MAILNAME}" | debconf-set-selections && \
    true

# Install Postfix
RUN apt-get -y --no-install-recommends install postfix

# Configure Postfix
RUN \
    postconf -e milter_protocol=2 && \
    postconf -e milter_default_action=accept && \
    postconf -e smtpd_milters=inet:${MC_MAIL_POSTFIX_OPENDKIM_HOST}:12301 && \
    postconf -e non_smtpd_milters=inet:${MC_MAIL_POSTFIX_OPENDKIM_HOST}:12301 && \
    true

# SMTP port
EXPOSE 25

# Start OpenDKIM
COPY bin/postfix.sh /

CMD ["/postfix.sh"]
