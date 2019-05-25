#
# Munin node
#

FROM dockermediacloud/mediacloud-base:latest

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
    # Install Munin node
    apt-get -y --no-install-recommends install munin-node && \
    #
    # Install patch for monkey-patching Munin
    apt-get -y --no-install-recommends install patch && \
    true

# Replace Munin's plugins with our own
RUN rm -rf /etc/munin/plugins/
COPY plugins/ /etc/munin/plugins/

# Set PostgreSQL credentials for plugins
ENV PGHOST mc_postgresql_pgbouncer
ENV PGPORT 6432
ENV PGUSER mediacloud
ENV PGPASSWORD mediacloud
ENV PGDATABASE mediacloud

# Set Solr credentials
ENV MC_SOLR_URL "http://mc_solr_shard:8983/solr"

# Configure Munin node
RUN \
    # Log to STDOUT
    sed -i -e "s/^log_file .*/log_file \/dev\/stdout/" /etc/munin/munin-node.conf && \
    # Run in foreground
    sed -i -e "s/^background .*/background 0/" /etc/munin/munin-node.conf && \
    # Don't fork out
    sed -i -e "s/^setsid .*/setsid 0/" /etc/munin/munin-node.conf && \
    # Set hostname to something that's not a container's ID
    sed -i -e "s/^#host_name .*/host_name mc_munin_node/" /etc/munin/munin-node.conf && \
    # Bind to IPv4 address only
    sed -i -e "s/^host .*/host 0.0.0.0/" /etc/munin/munin-node.conf && \
    # Allow everyone to connect
    echo "allow ^.*$" >> /etc/munin/munin-node.conf && \
    true

# Monkey-patch Munin's source for it to accept hostnames with underscores
# (see comment in munin-cron's Dockerfile)
COPY patches/Server.pm.diff /var/tmp/
RUN patch -p0 < /var/tmp/Server.pm.diff

# Create directory for PID file
RUN mkdir -p /var/run/munin/

# Expose Munin node's port
EXPOSE 4949

CMD ["munin-node", "--debug"]
