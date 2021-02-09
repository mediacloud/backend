#
# Munin node
#

FROM gcr.io/mcback/base:latest

# Install packages
RUN \
    #
    # Install plugin dependencies
    apt-get -y --no-install-recommends install \
        libdbd-pg-perl \
        libdbix-simple-perl \
        libjson-perl \
        liblwp-protocol-https-perl \
        libreadonly-perl \
        libwww-perl \
    && \
    #
    # Upgrade IO::Socket::SSL to be able to connect to servers using newer TLS protocols (api.mediacloud.org)
    apt-get -y --no-install-recommends install build-essential && \
    apt-get -y --no-install-recommends install libssl-dev && \
    /dl_to_stdout.sh https://raw.githubusercontent.com/skaji/cpm/0.988/cpm > /usr/bin/cpm && \
    chmod +x /usr/bin/cpm && \
    cpm install --global --no-prebuilt IO::Socket::SSL@2.066 && \
    rm -rf /root/.perl-cpm/ && \
    rm /usr/bin/cpm && \
    apt-get -y remove libssl-dev && \
    apt-get -y remove build-essential && \
    apt-get -y autoremove && \
    #
    # Install Munin node
    apt-get -y --no-install-recommends install munin-node && \
    #
    # Create directory for PID file
    mkdir -p /var/run/munin/ && \
    chown munin:munin /var/run/munin && \
    #
    true

# Replace Munin's plugins with our own
RUN rm -rf /etc/munin/plugins/
COPY plugins/ /etc/munin/plugins/

ENV \
    #
    # Set PostgreSQL credentials for plugins
    PGHOST=postgresql-pgbouncer \
    PGPORT=6432 \
    PGUSER=mediacloud \
    PGPASSWORD=mediacloud \
    PGDATABASE=mediacloud \
    #
    # Set Solr credentials
    MC_SOLR_URL="http://solr-shard-01:8983/solr"

# Configure Munin node
RUN \
    # Log to STDOUT
    sed -i -e "s/^log_file .*/log_file \/dev\/stdout/" /etc/munin/munin-node.conf && \
    # Run in foreground
    sed -i -e "s/^background .*/background 0/" /etc/munin/munin-node.conf && \
    # Don't fork out
    sed -i -e "s/^setsid .*/setsid 0/" /etc/munin/munin-node.conf && \
    # Set hostname to something that's not a container's ID
    sed -i -e "s/^#host_name .*/host_name munin-node/" /etc/munin/munin-node.conf && \
    # Bind to IPv4 address only
    sed -i -e "s/^host .*/host 0.0.0.0/" /etc/munin/munin-node.conf && \
    # Allow everyone to connect
    echo "allow ^.*$" >> /etc/munin/munin-node.conf && \
    true

# Expose Munin node's port
EXPOSE 4949

# No USER because docs say that munin-node is supposed to be run as root

CMD ["munin-node", "--debug"]
