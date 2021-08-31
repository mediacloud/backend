#
# PgBouncer
#

FROM gcr.io/mcback/postgresql-repo-base:latest

# Install PgBouncer
RUN \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
        echo "Installing Graviton2-optimized PgBouncer..." && \
        /dl_to_stdout.sh "https://github.com/mediacloud/postgresql-aws-graviton2/releases/download/13.3-1.pgdg20.04%2B1/pgbouncer_1.15.0-1.pgdg20.04+1_arm64.deb" > /var/tmp/pgbouncer.deb && \
        apt-get -y --no-install-recommends install \
            postgresql-common \
            libc-ares2 \
            libevent-2.1-7 \
        && \
        # FIXME dpkg doesn't exit with non-zero status if dependencies are missing
        dpkg -i /var/tmp/pgbouncer.deb && \
        rm /var/tmp/*.deb && \
        true; \
    else \
        echo "Installing generic build of PgBouncer..." && \
        apt-get -y --no-install-recommends install pgbouncer && \
        true; \
    fi; \
    #
    # Remove configuration that we're about to overwrite
    rm -rf /etc/pgbouncer && \
    #
    true

# Copy configuration
COPY conf/ /etc/pgbouncer/

# Server
EXPOSE 6432

# Copy wrapper script
COPY bin/pgbouncer.sh /

# No USER because wrapper script will run service as "postgres" itself

CMD ["/pgbouncer.sh"]
