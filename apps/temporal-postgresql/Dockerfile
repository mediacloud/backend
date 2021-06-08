#
# PostgreSQL server for Temporal's workflow storage
#

FROM gcr.io/mcback/postgresql-base:latest

USER root

RUN \
    mkdir -p \
        /opt/temporal-postgresql/bin/ \
        /opt/temporal-postgresql/schema/ \
    && \
    #
    # Install temporal-sql-tool
    # Keep version that's being used in sync with temporal-server
    mkdir -p /var/tmp/temporal/ && \
    /dl_to_stdout.sh "https://github.com/temporalio/temporal/releases/download/v1.9.2/temporal_1.9.2_linux_amd64.tar.gz" | \
        tar -zx -C /var/tmp/temporal/ && \
    mv \
        # Needed for creating the default namespace
        /var/tmp/temporal/tctl \
        # Needed for temporarily starting the server at build time to create
        # the default namespace
        /var/tmp/temporal/temporal-server \
        # Needed for initializing default schema
        /var/tmp/temporal/temporal-sql-tool \
        #
        /usr/bin/ && \
    rm -rf /var/tmp/temporal/ && \
    true

# Check out schema
RUN \
    apt-get -y --no-install-recommends install git && \
    mkdir -p /var/tmp/temporal/ && \
    cd /var/tmp/temporal/ && \
    git init && \
    git remote add origin https://github.com/temporalio/temporal.git && \
    # HEAD of "v1.9.2" tag:
    git fetch --depth 1 origin d3acf160e51deb60ac798746fc06fc5c46c46269 && \
    git checkout FETCH_HEAD && \
    mv schema/postgresql/* /opt/temporal-postgresql/schema/ && \
    cd / && \
    rm -rf /var/tmp/temporal/ && \
    apt-get -y remove git && \
    apt-get -y autoremove && \
    apt-get -y clean && \
    true

# Install envsubst for generating configuration
RUN apt-get -y --no-install-recommends install gettext-base

RUN mkdir -p /opt/temporal-server/config/
COPY temporal-config/* /opt/temporal-server/config/

# Allow a final mediacloud.yml to get generated
RUN chown postgres:postgres /opt/temporal-server/config/

# Copy helper scripts
COPY bin/* /opt/temporal-postgresql/bin/

USER postgres

# Initialize data volume, create users, a database, and initialize it with
# schema
# If a new empty volume gets mounted to /var/lib/postgresql/ upon
# container start, Docker will copy the files from the container to the volume
RUN /opt/temporal-postgresql/bin/initialize_schema.sh

# Remove the init script, Temporal server and configuration so that someone
# doesn't accidentally run it in production
USER root
RUN \
    rm -rf \
        /opt/temporal-postgresql/bin/initialize_schema.sh \
        /usr/bin/tctl \
        /usr/bin/temporal-server \
        /opt/temporal-server/ \
    && \
    true
USER postgres

ENV \
    PATH="/opt/temporal-postgresql/bin:${PATH}" \
    #
    # Make sure that we can connect via "psql" without sudoing into "postgres" user
    PGHOST=localhost \
    PGPORT=5432 \
    PGUSER=temporal \
    PGPASSWORD=temporal \
    PGDATABASE=temporal

# PostgreSQL data
VOLUME /var/lib/postgresql/

# Use our own wrapper script which runs schema upgrades first
CMD ["/opt/temporal-postgresql/bin/postgresql.sh"]
