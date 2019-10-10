#
# Munin HTTP server
#

FROM dockermediacloud/base:latest

# Install packages
RUN \
    #
    # Install Munin CGI scripts
    apt-get -y --no-install-recommends install munin && \
    #
    # Install lighttpd and FastCGI libs
    apt-get -y --no-install-recommends install \
        lighttpd \
        libcgi-fast-perl \
    && \
    #
    # Allow user to write to /dev/std[out|err]
    usermod -a -G tty munin && \
    #
    true

# Replace lighttpd's configuration
RUN rm -rf /etc/lighttpd/
COPY lighttpd/ /etc/lighttpd/

# Volume for RRD data (shared with munin-cron)
VOLUME /var/lib/munin/

# Volume for generated HTML (shared with munin-cron)
VOLUME /var/cache/munin/www/

# Web server's port
EXPOSE 4948

# No USER because lighttpd is configured to run under "munin" user

# Run lighttpd
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/lighttpd.conf"]
