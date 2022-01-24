#
# PostgreSQL base server
#

FROM gcr.io/mcback/postgresql-repo-base:latest

# Install PostgreSQL
RUN \
    # FIXME
    apt-get -y update && \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
        echo "Installing Graviton2-optimized PostgreSQL..." && \
        #
        # We might need newer libstdc++6 from PPA
        apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 60C317803A41BA51845E371A1E9377A2BA9EF27F && \
        echo "deb http://ppa.launchpad.net/ubuntu-toolchain-r/test/ubuntu focal main" > /etc/apt/sources.list.d/ubuntu-toolchain-r-test.list && \
        apt-get -y update && \
        apt-get -y install libstdc++6 && \
        #
        /dl_to_stdout.sh "https://github.com/mediacloud/postgresql-citus-aws-graviton2/releases/download/14.1-2.pgdg20.04%2B1/postgresql-14_14.1-2.pgdg20.04+1_arm64.deb" > /var/tmp/postgresql-14.deb && \
        /dl_to_stdout.sh "https://github.com/mediacloud/postgresql-citus-aws-graviton2/releases/download/14.1-2.pgdg20.04%2B1/postgresql-client-14_14.1-2.pgdg20.04+1_arm64.deb" > /var/tmp/postgresql-client-14.deb && \
        /dl_to_stdout.sh "https://github.com/mediacloud/postgresql-citus-aws-graviton2/releases/download/14.1-2.pgdg20.04%2B1/postgresql-plperl-14_14.1-2.pgdg20.04+1_arm64.deb" > /var/tmp/postgresql-plperl-14.deb && \
        /dl_to_stdout.sh "https://github.com/mediacloud/postgresql-citus-aws-graviton2/releases/download/14.1-2.pgdg20.04%2B1/libpq5_14.1-2.pgdg20.04+1_arm64.deb" > /var/tmp/libpq5.deb && \
        apt-get -y --no-install-recommends install \
            postgresql-client-common \
            postgresql-common \
            ssl-cert \
            libicu66 \
            libllvm11 \
            libxml2 \
            libxslt1.1 \
        && \
        # FIXME dpkg doesn't exit with non-zero status if dependencies are missing
        dpkg -i /var/tmp/libpq5.deb && \
        dpkg -i /var/tmp/postgresql-client-14.deb && \
        dpkg -i /var/tmp/postgresql-14.deb && \
        dpkg -i /var/tmp/postgresql-plperl-14.deb && \
        rm /var/tmp/*.deb && \
        true; \
    else \
        echo "Installing generic build of PostgreSQL..." && \
        apt-get -y --no-install-recommends install \
            postgresql-14 \
            postgresql-client-14 \
            postgresql-plperl-14 \
        && \
        true; \
    fi; \
    true

# Install WAL-G for backing up PostgreSQL
RUN \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
        sudo apt-get -y install xz-utils && \
        /dl_to_stdout.sh https://github.com/mediacloud/wal-g-aws-graviton2/releases/download/v1.1/wal-g-pg-ubuntu-20.04-arm64-graviton2.xz > /var/tmp/wal-g.xz && \
        cd /var/tmp/ && \
        xz -d wal-g.xz && \
        mv wal-g wal-g-pg-ubuntu-20.04-amd64 && \
        apt-get remove xz-utils && \
        true; \
    else \
        /dl_to_stdout.sh https://github.com/wal-g/wal-g/releases/download/v1.1/wal-g-pg-ubuntu-20.04-amd64.tar.gz > /var/tmp/wal-g.tar.gz && \
        cd /var/tmp/ && \
        #
        # Verify SHA1 so that we're sure about what we're installing
        echo "f7cc6bf4d3f8e36cf05ae7fdd03bd3a0906359a3 wal-g.tar.gz" > /var/tmp/wal-g.tar.gz.sha1 && \
        sha1sum -c wal-g.tar.gz.sha1 && \
        tar -zxf wal-g.tar.gz && \
        rm /var/tmp/wal-g.tar.gz* && \
        true; \
    fi; \
    #
    # Users are expected to use wal-g.sh wrapper instead of "wal-g" binary directly
    mv wal-g-pg-ubuntu-20.04-amd64 /usr/bin/_wal-g && \
    chmod +x /usr/bin/_wal-g && \
    true

# Make some run directories
RUN \
    mkdir -p /var/run/postgresql/14-main.pg_stat_tmp && \
    chown -R postgres:postgres /var/run/postgresql/14-main.pg_stat_tmp && \
    true

# Write our own configuration
RUN \
    rm -rf /etc/postgresql/14/ && \
    mkdir -p /etc/postgresql/14/extra/ && \
    true

COPY etc/postgresql/14/main/ /etc/postgresql/14/main/

RUN \
    #
    # This is where "generate_runtime_config.sh" script will write its memory settings
    # which it will auto-determine from available RAM on every run.
    touch /var/run/postgresql/postgresql-memory.conf && \
    chown postgres:postgres /var/run/postgresql/postgresql-memory.conf && \
    #
    # This is where "generate_runtime_config.sh" script will write WAL-G-related
    # configuration
    touch /var/run/postgresql/postgresql-walg.conf && \
    chown postgres:postgres /var/run/postgresql/postgresql-walg.conf && \
    #
    # This is where "generate_runtime_config.sh" script will write WAL-G
    # configuration to later be "source"'d in by wal-g.sh wrapper script
    touch /var/run/postgresql/walg.env && \
    chown postgres:postgres /var/run/postgresql/walg.env && \
    chmod 600 /var/run/postgresql/walg.env && \
    #
    true

# Copy helper scripts
RUN mkdir -p /opt/postgresql-base/
COPY bin/* /opt/postgresql-base/bin/

ENV \
    PATH="/opt/postgresql-base/bin:${PATH}" \
    #
    # Make sure that we can connect via "psql" without sudoing into "postgres" user
    # (PGUSER, PGPASSWORD and PGDATABASE will be set by sub-images of this image)
    PGHOST=localhost \
    PGPORT=5432

USER postgres

RUN \
    #
    # Remove APT-initialized data directory because it doesn't have the right
    # locale, doesn't use checksums etc.
    rm -rf /var/lib/postgresql/14/main/ && \
    #
    # Generate memory configuration in case we decide to start PostgreSQL at
    # build time
    /opt/postgresql-base/bin/generate_runtime_config.sh && \
    #
    # Run initdb
    mkdir -p /var/lib/postgresql/14/main/ && \
    /usr/lib/postgresql/14/bin/initdb \
        --pgdata=/var/lib/postgresql/14/main/ \
        --data-checksums \
        --encoding=UTF-8 \
        --lc-collate='en_US.UTF-8' \
        --lc-ctype='en_US.UTF-8' \
    && \
    #
    true

# VOLUME doesn't get set here as children of this image might amend the initial
# data directory somehow (e.g. pre-initialize it with some schema). Once you do
# that in the sub-image, don't forget to define "VOLUME /var/lib/postgresql/"
# afterwards!

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
