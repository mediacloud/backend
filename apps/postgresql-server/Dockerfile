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
    #
    # https://github.com/pypa/pip/issues/5221#issuecomment-382069604
    hash -r pip3 && \
    apt-get -y --no-install-recommends install build-essential python3-dev libffi-dev libpq-dev && \
    #
    # Install package to manage schema migrations
    pip3 install yandex-pgmigrate==1.0.6 && \
    #
    # Remove temporary dependencies
    apt-get -y remove build-essential python3-dev libffi-dev libpq-dev && \
    #
    # Cleanup
    apt-get -y autoremove && \
    rm -rf /root/.cache/ && \
    #
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

# Copy helper scripts, schema, migrations, pgmigrate callbacks/config
RUN mkdir -p /opt/mediacloud/
COPY bin/ /opt/mediacloud/bin/
COPY callbacks/ /opt/mediacloud/callbacks/
COPY migrations/ /opt/mediacloud/migrations/
COPY migrations.yml /opt/mediacloud/migrations.yml
RUN cd /opt/mediacloud

USER postgres

# Initialize data volume, create users + database
# If a new empty volume gets mounted to /var/lib/postgresql/ upon
# container start, Docker will copy the files from the container to the volume
RUN /opt/mediacloud/bin/initialize_db.sh

ENV \
    PATH="/opt/postgresql-server/bin:${PATH}" \
    #
    # Make sure that we can connect via "psql" without sudoing into "postgres" user
    PGHOST=localhost \
    PGPORT=5432 \
    PGUSER=mediacloud \
    PGPASSWORD=mediacloud \
    PGDATABASE=mediacloud

# Remove the init script so that someone doesn't accidentally run it in production
USER root
RUN rm /opt/mediacloud/bin/initialize_db.sh

FROM scratch as export-stage
COPY --from=build /tmp/mediawords.sql ./

FROM build
USER postgres

# PostgreSQL data
VOLUME /var/lib/postgresql/

# Use our own wrapper script which runs schema upgrades first
CMD ["/opt/postgresql-server/bin/postgresql.sh"]
