#!/bin/bash

#
# Copy Media Cloud's PostgreSQL configuration and restart PostgreSQL service
#
# Set MC_POSTGRESQL_PRODUCTION=1 to set up configuration properties designed
# for a production system.
#

set -u
set -o errexit

if [ "$EUID" -eq 0 ]; then
    echo "Please run this script from the user from which you intend to run Media Cloud services."
    exit 1
fi

psql --version || {
    echo "psql is not available, maybe PostgreSQL is not installed?"
    exit 1
}

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Path to Media Cloud's PostgreSQL general configuration file
MEDIACLOUD_CONF_SRC_FILE_PATH="$PWD/../config/postgresql-mediacloud.conf"
if [ ! -f "$MEDIACLOUD_CONF_SRC_FILE_PATH" ]; then
    echo "Media Cloud's PostgreSQL configuration file was not found at: $MEDIACLOUD_CONF_SRC_FILE_PATH"
    exit 1
fi

# Path to Media Cloud's PostgreSQL production configuration file
MEDIACLOUD_CONF_PRODUCTION_SRC_FILE_PATH="$PWD/../config/postgresql-mediacloud-production.conf"
if [ ! -f "$MEDIACLOUD_CONF_PRODUCTION_SRC_FILE_PATH" ]; then
    echo "Media Cloud's PostgreSQL production configuration file was not found at: $MEDIACLOUD_CONF_PRODUCTION_SRC_FILE_PATH"
    exit 1
fi

if [ `uname` == 'Darwin' ]; then
    # Mac OS X
    CONFIG_DIR="/usr/local/var/postgres/"
    POSTGRESQL_USER=`id -un`
else
    # Ubuntu
    CONFIG_DIR=$(ls -d /etc/postgresql/*/main/)
    POSTGRESQL_USER=`postgres`
fi

if [ $(echo $CONFIG_DIR | wc -l) -gt 1 ]; then
    echo "More than one PostgreSQL configuration was found at: $CONFIG_DIR"
    exit 1
fi

POSTGRESQL_CONF_FILE_PATH="$CONFIG_DIR/postgresql.conf"

if [ ! -f "$POSTGRESQL_CONF_FILE_PATH" ]; then
    echo "postgresql.conf was not found at: $POSTGRESQL_CONF_FILE_PATH"
    exit 1
fi

# Create include directory to load configuration from
CONF_D_DIR="$CONFIG_DIR/conf.d/"
sudo mkdir -p "$CONF_D_DIR"
sudo chown "$POSTGRESQL_USER" "$CONF_D_DIR"

PG_STAT_TMP_DIR="/var/run/postgresql/9.3-main.pg_stat_tmp/"
sudo mkdir -p "$PG_STAT_TMP_DIR"
sudo chown "$POSTGRESQL_USER" "$PG_STAT_TMP_DIR"

# Make PostgreSQL read from the include directory
if ! grep -q "MEDIA CLOUD CONFIGURATION" "$POSTGRESQL_CONF_FILE_PATH"; then
    echo "Enabling 'include_dir' in $POSTGRESQL_CONF_FILE_PATH..."

    sudo tee -a "$POSTGRESQL_CONF_FILE_PATH" <<EOF


#------------------------------------------------------------------------------
# MEDIA CLOUD CONFIGURATION
#------------------------------------------------------------------------------

# Include Media Cloud's and other configuration from conf.d
include_dir = 'conf.d'
EOF
fi

# File to copy Media Cloud's general configuration to
MEDIACLOUD_CONF_DST_FILE_PATH="$CONF_D_DIR/01mediacloud.conf"
if [ -f "$MEDIACLOUD_CONF_DST_FILE_PATH" ]; then
    echo "Media Cloud PostgreSQL configuration already exists, will overwrite: $MEDIACLOUD_CONF_DST_FILE_PATH"
fi

echo "Copying Media Cloud PostgreSQL configuration from $MEDIACLOUD_CONF_SRC_FILE_PATH to $MEDIACLOUD_CONF_DST_FILE_PATH..."
sudo cp "$MEDIACLOUD_CONF_SRC_FILE_PATH" "$MEDIACLOUD_CONF_DST_FILE_PATH"

if [ -z ${MC_POSTGRESQL_PRODUCTION+x} ]; then
    echo "MC_POSTGRESQL_PRODUCTION is unset, skipping production's configuration."
else

    # File to copy Media Cloud's general configuration to
    MEDIACLOUD_CONF_PRODUCTION_DST_FILE_PATH="$CONF_D_DIR/02mediacloud-production.conf"
    if [ -f "$MEDIACLOUD_CONF_PRODUCTION_DST_FILE_PATH" ]; then
        echo "Media Cloud PostgreSQL production configuration already exists, will overwrite: $MEDIACLOUD_CONF_PRODUCTION_DST_FILE_PATH"
    fi

    echo "Copying Media Cloud PostgreSQL production configuration from $MEDIACLOUD_CONF_PRODUCTION_SRC_FILE_PATH to $MEDIACLOUD_CONF_PRODUCTION_DST_FILE_PATH..."
    sudo cp "$MEDIACLOUD_CONF_PRODUCTION_SRC_FILE_PATH" "$MEDIACLOUD_CONF_PRODUCTION_DST_FILE_PATH"

fi

echo "Restarting PostgreSQL..."
if [ `uname` == 'Darwin' ]; then
    # Mac OS X
    brew services restart postgresql
else
    # Ubuntu
    sudo service postgresql restart
fi
