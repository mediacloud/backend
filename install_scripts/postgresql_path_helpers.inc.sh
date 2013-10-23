#
# PostgreSQL path helpers to take care of utility path differences among various platforms.
#
# This script not intended to be run directly.
#

function run_psql {
    local sql_command="$1"

    if [ `uname` == 'Darwin' ]; then
        # Mac OS X
        local run_psql_result=`/usr/local/bin/psql -c "$sql_command" 2>&1 || echo `
    else
        # assume Ubuntu
        local run_psql_result=`sudo su -l postgres -c "psql -c \" $sql_command \" 2>&1 " || echo `
    fi
    echo "$run_psql_result"
}

function run_psql_import {
    local sql_filename="$1"
    local db_name="$2"

    if [ `uname` == 'Darwin' ]; then
        # Mac OS X
        local run_psql_import_result=`/usr/local/bin/psql -f "$sql_filename" $db_name 2>&1 || echo `
    else
        # assume Ubuntu
        local run_psql_import_result=`sudo su -l postgres -c "psql -f \"$sql_filename\" $db_name 2>&1 " || echo `
    fi
    echo "$run_psql_import_result"
}

function run_pg_dump {
    local db_name="$1"
    local sql_filename="$2"

    if [ `uname` == 'Darwin' ]; then
        # Mac OS X
        local run_pg_dump_result=`/usr/local/bin/pg_dump $db_name > "$sql_filename" || echo `
    else
        # assume Ubuntu
        local run_pg_dump_result=`sudo su -l postgres -c "pg_dump $db_name > \"$sql_filename\" " || echo `
    fi
    echo "$run_pg_dump_result"
}

function run_dropdb {
    local db_name="$1"

    if [ `uname` == 'Darwin' ]; then
        # Mac OS X
        local run_dropdb_result=`/usr/local/bin/dropdb $db_name 2>&1 || echo `
    else
        # assume Ubuntu
        local run_dropdb_result=`sudo su -l postgres -c "dropdb $db_name 2>&1 " || echo `
    fi
    echo "$run_dropdb_result"
}

function run_createdb {
    local db_name="$1"

    CREATEDB_OPTIONS="--owner mediaclouduser"

    # Force UTF-8 encoding because some PostgreSQL installations default to
    # "LATIN1" and then LENGTH() and similar functions don't work correctly
    CREATEDB_OPTIONS="$CREATEDB_OPTIONS --encoding=UTF-8"
    CREATEDB_OPTIONS="$CREATEDB_OPTIONS --lc-collate=en_US.UTF-8"
    CREATEDB_OPTIONS="$CREATEDB_OPTIONS --lc-ctype=en_US.UTF-8"
    # "template1" is preinitialized with "LATIN1" encoding on some systems and
    # thus doesn't work, so using a cleaner "template0":
    CREATEDB_OPTIONS="$CREATEDB_OPTIONS --template=template0"

    if [ `uname` == 'Darwin' ]; then
        # Mac OS X
        local run_createdb_result=`/usr/local/bin/createdb $CREATEDB_OPTIONS $db_name 2>&1 || echo `
    else
        # assume Ubuntu
        local run_createdb_result=`sudo su -l postgres -c "createdb $CREATEDB_OPTIONS $db_name 2>&1 " || echo `
    fi
    echo "$run_createdb_result"
}
