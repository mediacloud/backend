#
# PostgreSQL upgrade scripts
#

FROM gcr.io/mcback/postgresql-base:latest

USER root

# Install Python 3 for running the upgrade script
RUN apt-get -y --no-install-recommends install python3

# Install packages
RUN \
    #
    # Install PostgreSQL 13 (version to upgrade from)
    apt-get -y --no-install-recommends install \
        postgresql-13 \
        postgresql-client-13 \
        postgresql-contrib-13 \
        postgresql-plperl-13 \
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
    mkdir -p /var/lib/postgresql/ && \
    chown -R postgres:postgres /var/lib/postgresql/ && \
    rm -rf /var/lib/postgresql/* && \
    #
    # Remove extra configurations leaving only the one from parent "postgresql-base"
    rm -rf /etc/postgresql/13/ && \
    #
    true

COPY bin/postgresql_upgrade.py /usr/bin/

# This is where the volume is supposed to be mounted
VOLUME /var/lib/postgresql/

USER postgres

CMD ["postgresql_upgrade.py"]
