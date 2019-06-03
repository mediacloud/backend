#
# OpenDKIM server
#

FROM dockermediacloud/base:latest

# Install packages
RUN \
    #
    # Install OpenDKIM
    apt-get -y --no-install-recommends install opendkim opendkim-tools && \
    true

# Configure OpenDKIM socket
RUN sed -i -e "s/^SOCKET=.*/SOCKET='inet:12301@localhost'/" /etc/default/opendkim

# Remove vendor configuration
RUN rm -rf /etc/opendkim/ /etc/opendkim.conf

COPY etc/opendkim.conf /etc/
COPY etc/opendkim/ /etc/opendkim/
RUN mkdir -p /etc/opendkim/keys/

# OpenDKIM port
EXPOSE 12301

# Volume with configuration and keys
VOLUME /etc/opendkim/

# Copy wrapper script
COPY bin/opendkim.sh /

# No USER because daemon will demote itself to "opendkim" user itself

CMD ["/opendkim.sh"]
