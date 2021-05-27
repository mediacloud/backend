#
# PostgreSQL upgrade scripts
#

FROM gcr.io/mcback/postgresql-server:latest

USER root

# Install Python 3 for running the upgrade script
RUN apt-get -y --no-install-recommends install python3

# Install packages
RUN \
    #
    # Install PostgreSQL 11 (oldest version)
    apt-get -y --no-install-recommends install \
        postgresql-11 \
        postgresql-client-11 \
        postgresql-contrib-11 \
        postgresql-plperl-11 \
    && \
    #
    # Install PostgreSQL 12 (intermediate version)
    apt-get -y --no-install-recommends install \
        postgresql-12 \
        postgresql-client-12 \
        postgresql-contrib-12 \
        postgresql-plperl-12 \
    && \
    #
    true

RUN \
    #
    # Make some run directories
    mkdir -p /var/run/postgres/ && \
    chown -R postgres:postgres /var/run/postgres/ && \
    #
    # Remove what might have gotten created in the parent image as we won't use it
    rm -rf /var/lib/postgresql/ && \
    mkdir /var/lib/postgresql/ && \
    #
    # Remove extra configurations leaving only the one from parent "postgresql-base"
    rm -rf /etc/postgresql/11/ && \
    rm -rf /etc/postgresql/12/ && \
    #
    true

COPY bin/postgresql_upgrade.py /usr/bin/

# This is where the volume is supposed to be mounted
VOLUME /var/lib/postgresql/

USER postgres

CMD ["postgresql_upgrade.py"]
