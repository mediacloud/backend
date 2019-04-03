#
# PostgreSQL server
#

FROM dockermediacloud/mediacloud-postgresql-base:latest

# Install packages
RUN \
    #
    # Install PostgreSQL
    apt-get -y --no-install-recommends install \
        postgresql-11 \
        postgresql-client-11 \
        postgresql-contrib-11 \
        postgresql-plperl-11 \
    && \
    true

# Make some run directories
RUN \
    mkdir -p /var/run/postgresql/11-main.pg_stat_tmp && \
    chown -R postgres:postgres /var/run/postgresql/11-main.pg_stat_tmp && \
    true

# Update static configuration
COPY conf/postgresql.conf /var/tmp/
RUN cat /var/tmp/postgresql.conf >> /etc/postgresql/11/main/postgresql.conf

# PostgreSQL data
VOLUME /var/lib/postgresql/11/main/

# Server
EXPOSE 5432

# Start PostgreSQL
COPY bin/postgresql_server.sh /
CMD ["sudo", "su", "-", "postgres", "/postgresql_server.sh"]
