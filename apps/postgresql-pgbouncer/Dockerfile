#
# PgBouncer
#

FROM gcr.io/mcback/postgresql-repo-base:latest

# Install PgBouncer
RUN \
    apt-get -y --no-install-recommends install pgbouncer && \
    rm -rf /etc/pgbouncer && \
    true

# Copy configuration
COPY conf/ /etc/pgbouncer/

# Server
EXPOSE 6432

# Copy wrapper script
COPY bin/pgbouncer.sh /

# No USER because wrapper script will run service as "postgres" itself

CMD ["/pgbouncer.sh"]
