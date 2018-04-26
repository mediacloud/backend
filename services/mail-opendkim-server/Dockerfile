#
# OpenDKIM server
#

FROM mediacloud-base:latest

# Domain that we will be signing for
ENV MC_MAIL_OPENDKIM_DOMAIN "mediacloud.org"
ENV MC_MAIL_OPENDKIM_HOSTNAME "mail"

# Install packages
RUN \
    #
    # Install rsyslog
    # (OpenDKIM is only able to log to syslog and not stdout / stderr)
    apt-get -y --no-install-recommends install rsyslog && \
    #
    # Install OpenDKIM
    apt-get -y --no-install-recommends install opendkim opendkim-tools && \
    true

# Configure OpenDKIM socket
RUN sed -i -e "s/SOCKET=.*/SOCKET='inet:12301@localhost'/" /etc/default/opendkim

# Create OpenDKIM configuration directories
RUN mkdir -p /etc/opendkim/keys/

# Copy configuration
COPY conf/opendkim/* /etc/opendkim/
COPY conf/rsyslog/rsyslog.conf /etc/

# Write some dynamic configuration
RUN \
    echo "${MC_MAIL_OPENDKIM_HOSTNAME}._domainkey.${MC_MAIL_OPENDKIM_DOMAIN} ${MC_MAIL_OPENDKIM_DOMAIN}:${MC_MAIL_OPENDKIM_HOSTNAME}:/etc/opendkim/keys/${MC_MAIL_OPENDKIM_HOSTNAME}.private" \
        > /etc/opendkim/KeyTable && \
    echo "*@${MC_MAIL_OPENDKIM_DOMAIN} ${MC_MAIL_OPENDKIM_HOSTNAME}._domainkey.${MC_MAIL_OPENDKIM_DOMAIN}" \
        > /etc/opendkim/SigningTable && \
    true

# Generate and print signing key
RUN \
    opendkim-genkey -s "${MC_MAIL_OPENDKIM_HOSTNAME}" -d "${MC_MAIL_OPENDKIM_DOMAIN}" -D /etc/opendkim/keys/ && \
    chown opendkim:opendkim "/etc/opendkim/keys/${MC_MAIL_OPENDKIM_HOSTNAME}.private" && \
    echo && \
    echo "OpenDKIM signing key for ${MC_MAIL_OPENDKIM_HOSTNAME}.${MC_MAIL_OPENDKIM_DOMAIN}: " && \
    echo && \
    cat "/etc/opendkim/keys/${MC_MAIL_OPENDKIM_HOSTNAME}.txt" && \
    echo && \
    true

# OpenDKIM port
EXPOSE 12301

# Start OpenDKIM
COPY bin/opendkim.sh /
CMD ["/opendkim.sh"]
