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

# Allow mc_postgresql_pgbouncer to connect using a password
RUN echo "host all mediacloud samenet md5" >> /etc/postgresql/11/main/pg_hba.conf

# Copy helper scripts
COPY bin/postgresql_server.sh bin/initialize_postgresql_db.sh /

# Initialize data volume, create users and a database
# If a new empty volume gets mounted to /var/lib/postgresql/ upon
# container start, Docker will copy the files from the container to the volume
RUN \
    echo "Creating initial database..." && \
    rm -rf /var/lib/postgresql/11/main/ && \
    sudo su - postgres /initialize_postgresql_db.sh && \
    echo "Done creating initial database." && \
    true

# PostgreSQL data
VOLUME /var/lib/postgresql/11/main/

# Server
EXPOSE 5432

CMD ["sudo", "su", "-", "postgres", "/postgresql_server.sh"]
