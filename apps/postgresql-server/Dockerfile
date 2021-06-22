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
