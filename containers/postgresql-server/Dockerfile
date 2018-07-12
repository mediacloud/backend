#
# PostgreSQL server
#

FROM mediacloud-postgresql-base:latest

# Install packages
RUN \
    #
    # Install PostgreSQL
    apt-get -y --no-install-recommends install \
        postgresql-10 \
        postgresql-client-10 \
        postgresql-contrib-10 \
        postgresql-plperl-10 \
        postgresql-server-dev-10 \
    && \
    true

# Make some run directories
RUN \
    mkdir -p /var/run/postgresql/10-main.pg_stat_tmp && \
    chown -R postgres:postgres /var/run/postgresql/10-main.pg_stat_tmp && \
    true

# Update static configuration
COPY conf/postgresql.conf /var/tmp/
RUN cat /var/tmp/postgresql.conf >> /etc/postgresql/10/main/postgresql.conf

# PostgreSQL data
VOLUME /var/lib/postgresql/10/main/

# Server
EXPOSE 5432

# Start PostgreSQL
COPY bin/postgres.sh /
CMD ["sudo", "su", "-", "postgres", "/postgres.sh"]
