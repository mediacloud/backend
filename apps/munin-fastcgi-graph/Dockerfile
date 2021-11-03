#
# Munin FastCGI graph generator
#

FROM mc2021/base:latest

# Install packages
RUN \
    #
    # Install Munin CGI scripts
    apt-get -y --no-install-recommends install munin && \
    #
    # Install spawn-fcgi which will spawn Munin's FastCGI workers
    apt-get -y --no-install-recommends install spawn-fcgi libcgi-fast-perl && \
    #
    # Create directory for FastCGI sockets
    mkdir /var/run/munin/ && \
    chown munin:munin /var/run/munin/ && \
    #
    # Symlink logs to /dev/null
    # (we can't write to /proc/1/fd/1 from unprivileged user, but --debug prints the same log to STDERR)
    rm /var/log/munin/*.log && \
    ln -s /dev/null /var/log/munin/munin-cgi-graph.log && \
    #
    true

# Copy wrapper script
COPY bin/munin-fastcgi-graph.sh /

# Volume for RRD data (shared with munin-cron)
VOLUME /var/lib/munin/

# FastCGI worker's port
EXPOSE 22334

# No USER because spawn-fcgi runs as "munin"

# Run FastCGI worker
CMD ["/munin-fastcgi-graph.sh"]
