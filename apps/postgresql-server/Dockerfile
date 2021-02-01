#
# PostgreSQL server
#

FROM gcr.io/mcback/postgresql-base:latest

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

# Write our own configuration
RUN rm -rf /etc/postgresql/11/main/
COPY conf/ /etc/postgresql/11/main/

# This is where "update_memory_config.sh" script will write its memory settings
# which it will auto-determine from available RAM on every run.
RUN \
    touch /var/run/postgresql/postgresql-memory.conf && \
    chown postgres:postgres /var/run/postgresql/postgresql-memory.conf && \
    true

# Copy helper scripts, schema, migrations
RUN mkdir -p /opt/mediacloud/
COPY bin/ /opt/mediacloud/bin/
COPY schema/ /opt/mediacloud/schema/

USER postgres

# Initialize data volume, create users, a database, and initialize it with
# schema
# If a new empty volume gets mounted to /var/lib/postgresql/ upon
# container start, Docker will copy the files from the container to the volume
RUN /opt/mediacloud/bin/initialize_schema.sh

ENV \
    PATH="/opt/mediacloud/bin:${PATH}" \
    #
    # Make sure that we can connect via "psql" without sudoing into "postgres" user
    PGHOST=localhost \
    PGPORT=5432 \
    PGUSER=mediacloud \
    PGPASSWORD=mediacloud \
    PGDATABASE=mediacloud

# Remove the init script so that someone doesn't accidentally run it in
# production
USER root
RUN rm /opt/mediacloud/bin/initialize_schema.sh
USER postgres

# PostgreSQL data
VOLUME /var/lib/postgresql/

# SIGTERM (Docker's default) will initiate PostgreSQL's "Smart Shutdown" mode
# which will then wait for the current transactions to finish. If there are
# active long-running queries, Docker will wait for "stop_grace_period", run
# out of patience and SIGKILL the process, forcing PostgreSQL to recover the
# database on restart.
# So, instead we stop the database with SIGINT which triggers "Fast Shutdown":
# active connections get terminated, and PostgreSQL shuts down considerably
# faster and safer.
STOPSIGNAL SIGINT

# Server
EXPOSE 5432

CMD ["/opt/mediacloud/bin/postgresql_server.sh"]
