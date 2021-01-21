#
# Main backend PostgreSQL server
#

FROM gcr.io/mcback/postgresql-base:latest

USER root
RUN \
    mkdir -p \
        /opt/postgresql-server/bin/ \
        /opt/postgresql-server/schema/ \
    && \
    apt-get -y --no-install-recommends install python3 python3-pip python3-setuptools && \
    #
    # Upgrade Pip
    pip3 install -U pip && \
    # https://github.com/pypa/pip/issues/5221#issuecomment-382069604
    hash -r pip3 && \
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

# Install package to manage schema migrations
RUN \
    pip3 install yandex-pgmigrate==1.0.6 && \
    rm -rf /root/.cache/ && \
    true

# Copy helper scripts, schema, migrations
COPY bin/* /opt/postgresql-server/bin/
COPY schema/ /opt/postgresql-server/schema/

# Initialize data volume, create users, a database, and initialize it with
# schema
# If a new empty volume gets mounted to /var/lib/postgresql/ upon
# container start, Docker will copy the files from the container to the volume
USER postgres
RUN /opt/postgresql-server/bin/initialize_schema.sh

# Remove the init script so that someone doesn't accidentally run it in
# production
USER root
RUN rm /opt/postgresql-server/bin/initialize_schema.sh
USER postgres

ENV \
    PATH="/opt/postgresql-server/bin:${PATH}" \
    #
    # Make sure that we can connect via "psql" without sudoing into "postgres" user
    PGHOST=localhost \
    PGPORT=5432 \
    PGUSER=mediacloud \
    PGPASSWORD=mediacloud \
    PGDATABASE=mediacloud

# PostgreSQL data
VOLUME /var/lib/postgresql/

# Use our own wrapper script which runs schema upgrades first
CMD ["/opt/postgresql-server/bin/postgresql.sh"]
