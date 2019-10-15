#
# Munin node
#

FROM dockermediacloud/base:latest

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
    # Allow user to write to /dev/std[out|err]
    usermod -a -G tty munin && \
    #
    true

# Replace Munin's plugins with our own
RUN rm -rf /etc/munin/plugins/
COPY plugins/ /etc/munin/plugins/

# Set PostgreSQL credentials for plugins
ENV PGHOST postgresql-pgbouncer
ENV PGPORT 6432
ENV PGUSER mediacloud
ENV PGPASSWORD mediacloud
ENV PGDATABASE mediacloud

# Set Solr credentials
ENV MC_SOLR_URL "http://solr-shard-1:8983/solr"

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

# Create directory for PID file
RUN \
    mkdir -p /var/run/munin/ && \
    chown munin:munin /var/run/munin && \
    true

# Expose Munin node's port
EXPOSE 4949

# No USER because docs say that munin-node is supposed to be run as root

CMD ["munin-node", "--debug"]
