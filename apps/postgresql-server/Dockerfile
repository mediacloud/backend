#
# Main backend PostgreSQL server
#

FROM gcr.io/mcback/postgresql-base:latest

USER root
RUN \
    #
    # FIXME
    apt-get -y update && \
    #
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
    apt-get -y clean && \
    rm -rf /root/.cache/ && \
    #
    true

# Copy helper scripts, migrations, pgmigrate callbacks/config, create schema dir
RUN \
    mkdir -p \
        /opt/postgresql-server/bin/ \
        /opt/postgresql-server/pgmigrate \
    && \
    chmod ugo+rw /opt/postgresql-server/pgmigrate && \
    true

# Install Citus Data
RUN \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
        /dl_to_stdout.sh "https://github.com/mediacloud/postgresql-citus-aws-graviton2/releases/download/14.1-2.pgdg20.04%2B1/postgresql-14-citus-10.2_10.2.3.citus-1_arm64.deb" > /var/tmp/citus.deb && \
        apt-get -y --no-install-recommends install \
            libcurl4-gnutls-dev \
        && \
        dpkg -i /var/tmp/citus.deb && \
        rm /var/tmp/*.deb && \
        true; \
    else \
        curl -fsSL https://repos.citusdata.com/community/gpgkey | apt-key add - && \
        echo "deb https://repos.citusdata.com/community/ubuntu/ focal main" \
            > /etc/apt/sources.list.d/citusdata_community.list && \
        apt-get -y update && \
        sudo apt-get -y install postgresql-14-citus-10.2 && \
        true; \
    fi; \
    true

COPY etc/postgresql/14/extra/ /etc/postgresql/14/extra/

# Copy helper scripts, schema, migrations
COPY bin/* /opt/postgresql-server/bin/
COPY pgmigrate/ /opt/postgresql-server/pgmigrate

# Initialize data volume, create users + database
# If a new empty volume gets mounted to /var/lib/postgresql/ upon
# container start, Docker will copy the files from the container to the volume

USER postgres
RUN \
    unset PGHOST PGPORT && \
    /opt/postgresql-server/bin/initialize_db.sh && \
    true

# Remove the init script so that someone doesn't accidentally run it in
# production
USER root
RUN rm /opt/postgresql-server/bin/initialize_db.sh

# dump schema file for reference in development (run ./dev/get_schema.sh to get local copy)
RUN mv /opt/postgresql-server/pgmigrate/mediawords.sql /opt/mediawords.sql

USER postgres
ENV \
    PATH="/opt/postgresql-server/bin:${PATH}" \
    #
    # Make sure that we can connect via "psql" without sudoing into "postgres" user
    PGUSER=mediacloud \
    PGPASSWORD=mediacloud \
    PGDATABASE=mediacloud

# PostgreSQL data
VOLUME /var/lib/postgresql/

# Use our own wrapper script which runs schema upgrades first
CMD ["/opt/postgresql-server/bin/postgresql.sh"]
