#!/bin/bash
#
# PostgreSQL upgrade script
#

id

read -r -d '' USAGE <<'EOF'
docker run -it \
    -v ~/Downloads/postgres_11_vol/:/var/lib/postgresql/ \
    gcr.io/mcback/postgresql-upgrade \
    postgresql-upgrade.sh 11 12
EOF

set -u
set -e

POSTGRES_DATA_DIR="/var/lib/postgresql"

if [ "$#" -ne 2 ]; then
    echo "Usage: $USAGE"
fi

if [ ! -x "${POSTGRES_DATA_DIR}" ]; then
    echo "${POSTGRES_DATA_DIR} does not exist or is unaccessible."
    exit 1
fi

if [ "$(whoami)" != "postgres" ]; then
    echo "This script is to be run as 'postgres' user."
    exit 1
fi

OLD_VERSION="$1"
NEW_VERSION="$2"

if [ "${OLD_VERSION}" -ge "${NEW_VERSION}" ]; then
    echo "New version ${NEW_VERSION} is not newer than old version ${OLD_VERSION}."
    exit 1
fi
if [ "${OLD_VERSION}" -ne $(("${NEW_VERSION}"-1)) ]; then
    echo "New version ${NEW_VERSION} is not only one major version newer than"
    echo "${OLD_VERSION}."
    exit 1
fi

echo "Will upgrade from ${OLD_VERSION} to ${NEW_VERSION}"

OLD_DATA_DIR="${POSTGRES_DATA_DIR}/${OLD_VERSION}/"
NEW_DATA_DIR="${POSTGRES_DATA_DIR}/${NEW_VERSION}/"

if [ ! -x "${OLD_DATA_DIR}" ]; then
    echo "Old data directory ${OLD_DATA_DIR} does not exist or is"
    echo "unaccessible; forgot to mount it?"
    exit 1
fi

if [ -d "${NEW_DATA_DIR}" ]; then
    echo "New data directory ${NEW_DATA_DIR} already exists; if the previous"
    echo "attempt to upgrade failed, run something like this:"
    echo
    echo "    rm -rf ${NEW_DATA_DIR}"
    echo
    echo "on a container, or adjust the path on the host."
    exit 1
fi

OLD_MAIN_DIR="${OLD_DATA_DIR}/main/"
NEW_MAIN_DIR="${NEW_DATA_DIR}/main/"

if [ ! -x "${OLD_MAIN_DIR}" ]; then
    echo "Old main directory ${OLD_MAIN_DIR} does not exist or is unaccessible."
    exit 1
fi
if [ ! -r "${OLD_MAIN_DIR}/PG_VERSION" ]; then
    echo "${OLD_MAIN_DIR}/PG_VERSION does not exist or is unaccessible."
    exit 1
fi

if [ -f "${OLD_MAIN_DIR}/postmaster.pid" ]; then
    echo "postmaster.pid exists in ${OLD_MAIN_DIR}; is the database running?"
    exit 1
fi

# Create run directories
mkdir -p "/var/run/postgresql/${OLD_VERSION}-main.pg_stat_tmp/"
mkdir -p "/var/run/postgresql/${NEW_VERSION}-main.pg_stat_tmp/"

# Remove cruft that might have been left over from last attempt to do the upgrade
rm -f /var/lib/postgresql/pg_*.log
rm -f /var/lib/postgresql/pg_*.custom
rm -f /var/lib/postgresql/pg_upgrade_dump_globals.sql

OLD_BIN_DIR="/usr/lib/postgresql/${OLD_VERSION}/bin/"
NEW_BIN_DIR="/usr/lib/postgresql/${NEW_VERSION}/bin/"

if [ ! -x "${OLD_BIN_DIR}" ]; then
    echo "Old binaries directory ${OLD_BIN_DIR} does not exist or is unaccessible."
    exit 1
fi
if [ ! -x "${NEW_BIN_DIR}" ]; then
    echo "New binaries directory ${NEW_BIN_DIR} does not exist or is unaccessible."
    exit 1
fi

NEW_INITDB="${NEW_BIN_DIR}/initdb"
if [ ! -x "${NEW_INITDB}" ]; then
    echo "New initdb at ${NEW_INITDB} does not exist."
    exit 1
fi

NEW_PG_UPGRADE="${NEW_BIN_DIR}/pg_upgrade"
if [ ! -x "${NEW_PG_UPGRADE}" ]; then
    echo "New pg_upgrade at ${NEW_PG_UPGRADE} does not exist."
    exit 1
fi

OLD_PORT=50432
NEW_PORT=50433

echo "Updating memory configuration..."
/opt/postgresql-base/bin/update_memory_config.sh

OLD_TMP_CONF_DIR="/var/tmp/postgresql/conf/${OLD_VERSION}"
NEW_TMP_CONF_DIR="/var/tmp/postgresql/conf/${NEW_VERSION}"

echo "Creating temporary configurations for both instances..."
if [ "$(ls /etc/postgresql/ | wc -l)" -ne "1" ]; then
    echo "More than one PostgreSQL configuration has been found:"
    ls /etc/postgresql/
    exit 1
fi
mkdir -p "${OLD_TMP_CONF_DIR}"
mkdir -p "${NEW_TMP_CONF_DIR}"
cd /etc/postgresql/$(ls /etc/postgresql/)/main/
if [ ! -r "postgresql.conf" ]; then
    echo "postgresql.conf was not found in $(pwd)."
    exit 1
fi
cp -R * "${OLD_TMP_CONF_DIR}"
cp -R * "${NEW_TMP_CONF_DIR}"

cat << EOF >> "${OLD_TMP_CONF_DIR}/postgresql.conf"

port = ${OLD_PORT}
data_directory = '/var/lib/postgresql/${OLD_VERSION}/main'
hba_file = '${OLD_TMP_CONF_DIR}/pg_hba.conf'
ident_file = '${OLD_TMP_CONF_DIR}/pg_ident.conf'
external_pid_file = '/var/run/postgresql/${OLD_VERSION}-main.pid'
cluster_name = '${OLD_VERSION}/main'
stats_temp_directory = '/var/run/postgresql/${OLD_VERSION}-main.pg_stat_tmp'

EOF

RAM_SIZE=$(/container_memory_limit.sh)
NEW_MAINTENANCE_WORK_MEM=$((RAM_SIZE / 10))

cat << EOF >> "${NEW_TMP_CONF_DIR}/postgresql.conf"

port = ${NEW_PORT}
data_directory = '/var/lib/postgresql/${NEW_VERSION}/main'
hba_file = '${NEW_TMP_CONF_DIR}/pg_hba.conf'
ident_file = '${NEW_TMP_CONF_DIR}/pg_ident.conf'
external_pid_file = '/var/run/postgresql/${NEW_VERSION}-main.pid'
cluster_name = '${NEW_VERSION}/main'
stats_temp_directory = '/var/run/postgresql/${NEW_VERSION}-main.pg_stat_tmp'

maintenance_work_mem = ${NEW_MAINTENANCE_WORK_MEM}MB

EOF

echo "Running initdb..."
mkdir -p "${NEW_MAIN_DIR}"
"${NEW_INITDB}" \
    --pgdata="${NEW_MAIN_DIR}" \
    --data-checksums \
    --encoding=UTF-8 \
    --lc-collate='en_US.UTF-8' \
    --lc-ctype='en_US.UTF-8'

cd "${POSTGRES_DATA_DIR}"

echo "Testing if clusters are compatible..."
time "${NEW_PG_UPGRADE}" \
    --jobs=`nproc --all` \
    --old-bindir="${OLD_BIN_DIR}" \
    --new-bindir="${NEW_BIN_DIR}" \
    --old-datadir="${OLD_MAIN_DIR}" \
    --new-datadir="${NEW_MAIN_DIR}" \
    --old-port="${OLD_PORT}" \
    --new-port="${NEW_PORT}" \
    --old-options=" -c config_file=${OLD_TMP_CONF_DIR}/postgresql.conf" \
    --new-options=" -c config_file=${NEW_TMP_CONF_DIR}/postgresql.conf" \
    --link \
    --check \
    --verbose

echo "Upgrading..."
time "${NEW_PG_UPGRADE}" \
    --jobs=`nproc --all` \
    --old-bindir="${OLD_BIN_DIR}" \
    --new-bindir="${NEW_BIN_DIR}" \
    --old-datadir="${OLD_MAIN_DIR}" \
    --new-datadir="${NEW_MAIN_DIR}" \
    --old-port="${OLD_PORT}" \
    --new-port="${NEW_PORT}" \
    --old-options=" -c config_file=${OLD_TMP_CONF_DIR}/postgresql.conf" \
    --new-options=" -c config_file=${NEW_TMP_CONF_DIR}/postgresql.conf" \
    --link \
    --verbose
