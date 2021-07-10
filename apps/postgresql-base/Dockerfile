#
# PostgreSQL base server
#

FROM mc2021/postgresql-repo-base:latest

# Install packages
RUN \
    #
    # Install PostgreSQL
    apt-get -y --no-install-recommends install \
        postgresql-13 \
        postgresql-client-13 \
        postgresql-contrib-13 \
        postgresql-plperl-13 \
    && \
    true

# Make some run directories
RUN \
    mkdir -p /var/run/postgresql/13-main.pg_stat_tmp && \
    chown -R postgres:postgres /var/run/postgresql/13-main.pg_stat_tmp && \
    true

# Write our own configuration
RUN rm -rf /etc/postgresql/13/main/
COPY conf/ /etc/postgresql/13/main/

# This is where "update_memory_config.sh" script will write its memory settings
# which it will auto-determine from available RAM on every run.
RUN \
    touch /var/run/postgresql/postgresql-memory.conf && \
    chown postgres:postgres /var/run/postgresql/postgresql-memory.conf && \
    true

# Copy helper scripts
RUN mkdir -p /opt/postgresql-base/
COPY bin/* /opt/postgresql-base/bin/

USER postgres

RUN \
    #
    # Remove APT-initialized data directory because it doesn't have the right
    # locale, doesn't use checksums etc.
    rm -rf /var/lib/postgresql/13/main/ && \
    #
    # Update memory configuration in case we decide to start PostgreSQL at
    # build time
    # Update memory configuration
    /opt/postgresql-base/bin/update_memory_config.sh && \
    #
    # Run initdb
    mkdir -p /var/lib/postgresql/13/main/ && \
    /usr/lib/postgresql/13/bin/initdb \
        --pgdata=/var/lib/postgresql/13/main/ \
        --data-checksums \
        --encoding=UTF-8 \
        --lc-collate='en_US.UTF-8' \
        --lc-ctype='en_US.UTF-8' \
    && \
    true

# VOLUME doesn't get set here as children of this image might amend the initial
# data directory somehow (e.g. pre-initialize it with some schema). Once you do
# that in the sub-image, don't forget to define VOLUME afterwards!

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

# *Not* adding /opt/postgresql-base/ to $PATH so that users get to pick which
# specific version of "postgresql.sh" to run

CMD ["/opt/postgresql-base/bin/postgresql.sh"]
