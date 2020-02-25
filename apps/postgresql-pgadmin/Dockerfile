#
# pgAdmin
#

FROM dockermediacloud/postgresql-base:latest

# Copy pgAdmin4's requirements
COPY pgadmin-requirements.txt /var/tmp/

RUN \
    #
    # Install PostgreSQL utilities to do backups etc.
    apt-get -y --no-install-recommends install postgresql-client-11 && \
    #
    # Install dependencies
    apt-get -y --no-install-recommends install python3 python3-pip python3-setuptools && \
    #
    # Upgrade Pip
    pip3 install -U pip && \
    # https://github.com/pypa/pip/issues/5221#issuecomment-382069604
    hash -r pip3 && \
    #
    # Install temporary dependencies to be able to build pgAdmin
    apt-get -y --no-install-recommends install build-essential python3-dev libffi-dev && \
    #
    # Install pgAdmin's requirements
    cd /var/tmp/ && \
    pip3 install -r pgadmin-requirements.txt && \
    rm pgadmin-requirements.txt && \
    #
    # Install pgAdmin
    pip3 install https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v4.18/pip/pgadmin4-4.18-py2.py3-none-any.whl && \
    #
    # Install Gunicorn for serving web pages
    pip3 install gunicorn==19.9.0 && \
    #
    # Remove temporary dependencies
    apt-get -y remove build-essential python3-dev libffi-dev && \
    #
    # Cleanup
    apt-get -y autoremove && \
    rm -rf /root/.cache/ && \
    #
    true

# Some utilities assume that some version of Python is available as "python"
RUN ln -s /usr/bin/python3 /usr/bin/python

# Set up logging
# (stuff gets logged to console so we just forward logs to /dev/null)
RUN \
    mkdir -p /var/log/pgadmin/ && \
    rm -f /var/log/pgadmin/pgadmin4.log && \
    ln -s /dev/null /var/log/pgadmin/pgadmin4.log && \
    true

# Copy .pgpass file
RUN mkdir -p /var/lib/pgadmin/storage/mediacloud_mediacloud.org/
COPY mediacloud.pgpass /var/lib/pgadmin/storage/mediacloud_mediacloud.org
RUN chmod 0600 /var/lib/pgadmin/storage/mediacloud_mediacloud.org/mediacloud.pgpass
# Set environment variable for "pg_dump" and similar utilities to use
ENV PGPASSFILE=/var/lib/pgadmin/storage/mediacloud_mediacloud.org/mediacloud.pgpass

# Set up pgAdmin
COPY mediacloud-servers.json /var/tmp/
RUN \
    #
    # Configure path to PostgreSQL binaries
    echo 'DEFAULT_BINARY_PATHS = {"pg": "/usr/bin", "ppas": "", "gpdb": ""}' \
        >> /usr/local/lib/python3.5/dist-packages/pgadmin4/config_distro.py && \
    #
    # Make pgAdmin listen to all interfaces
    echo 'DEFAULT_SERVER = "127.0.0.1"' \
        >> /usr/local/lib/python3.5/dist-packages/pgadmin4/config_distro.py && \
    #
    # Configure mail server (although we won't be sending much mail)
    echo 'MAIL_SERVER = "mail-postfix-server"' \
        >> /usr/local/lib/python3.5/dist-packages/pgadmin4/config_distro.py && \
    #
    # Disable upgrade checks
    echo 'UPGRADE_CHECK_ENABLED = False' \
        >> /usr/local/lib/python3.5/dist-packages/pgadmin4/config_distro.py && \
    #
    # Initialize default configuration
    export PGADMIN_SETUP_EMAIL="mediacloud@mediacloud.org" && \
    export PGADMIN_SETUP_PASSWORD="mediacloud" && \
    python3 /usr/local/lib/python3.5/dist-packages/pgadmin4/setup.py \
        --load-servers /var/tmp/mediacloud-servers.json \
        --user "$PGADMIN_SETUP_EMAIL" \
        && \
    unset PGADMIN_SETUP_EMAIL && \
    unset PGADMIN_SETUP_PASSWORD && \
    rm /var/tmp/mediacloud-servers.json && \
    true

# Copy wrapper script
COPY pgadmin.sh /

# pgAdmin data
VOLUME /var/lib/pgadmin/

# pgAdmin port
EXPOSE 5050

# Run pgAdmin
CMD ["/pgadmin.sh"]
