#
# PostgreSQL server
#

FROM dockermediacloud/postgresql-base:latest

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
RUN chown postgres:postgres /etc/postgresql/11/main/postgresql-memory.conf

# Copy helper scripts, schema, migrations
RUN mkdir -p /opt/mediacloud/
COPY bin/ /opt/mediacloud/bin/
COPY schema/ /opt/mediacloud/schema/

USER postgres

ENV PATH="/opt/mediacloud/bin:${PATH}"

# Initialize data volume, create users, a database, and initialize it with
# schema
# If a new empty volume gets mounted to /var/lib/postgresql/ upon
# container start, Docker will copy the files from the container to the volume
RUN initialize_schema.sh

# Remove the init script so that someone doesn't accidentally run it in
# production
USER root
RUN rm /opt/mediacloud/bin/initialize_schema.sh
USER postgres

# Make sure that we can connect via "psql" without sudoing into "postgres" user
ENV PGHOST localhost
ENV PGPORT 5432
ENV PGUSER mediacloud
ENV PGPASSWORD mediacloud
ENV PGDATABASE mediacloud

# PostgreSQL data
VOLUME /var/lib/postgresql/

# Server
EXPOSE 5432

CMD ["/opt/mediacloud/bin/postgresql_server.sh"]
