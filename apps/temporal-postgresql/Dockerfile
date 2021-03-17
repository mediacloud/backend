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
    # FIXME use upstream CI builds once they start working
    # Keep version that's being used in sync with temporal-server
    mkdir -p /var/tmp/temporal/ && \
    /dl_to_stdout.sh "https://github.com/mediacloud/temporal-ci-builds/releases/download/v1.7.0-gr/temporal-ci-builds_1.7.0-gr_linux_amd64.tar.gz" | \
        tar -zx -C /var/tmp/temporal/ && \
    mv /var/tmp/temporal/temporal-sql-tool /usr/bin/ && \
    rm -rf /var/tmp/temporal/ && \
    true

# Check out schema
RUN \
    apt-get -y --no-install-recommends install git && \
    mkdir -p /var/tmp/temporal/ && \
    cd /var/tmp/temporal/ && \
    git init && \
    git remote add origin https://github.com/temporalio/temporal.git && \
    # HEAD of "v1.7.0" tag:
    git fetch --depth 1 origin e3496b1c51bfaaae8142b78e4032cc791de8a76f && \
    git checkout FETCH_HEAD && \
    mv schema/postgresql/* /opt/temporal-postgresql/schema/ && \
    cd / && \
    rm -rf /var/tmp/temporal/ && \
    apt-get -y remove git && \
    apt-get -y autoremove && \
    apt-get -y clean && \
    true

# Copy helper scripts
COPY bin/* /opt/temporal-postgresql/bin/

USER postgres

# Initialize data volume, create users, a database, and initialize it with
# schema
# If a new empty volume gets mounted to /var/lib/postgresql/ upon
# container start, Docker will copy the files from the container to the volume
RUN /opt/temporal-postgresql/bin/initialize_schema.sh

# Remove the init script so that someone doesn't accidentally run it in
# production
USER root
RUN rm /opt/temporal-postgresql/bin/initialize_schema.sh
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
