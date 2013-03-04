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

    if [ `uname` == 'Darwin' ]; then
        # Mac OS X
        local run_createdb_result=`/usr/local/bin/createdb --owner mediaclouduser $db_name 2>&1 || echo `
    else
        # assume Ubuntu
        local run_createdb_result=`sudo su -l postgres -c "createdb --owner mediaclouduser $db_name 2>&1 " || echo `
    fi
    echo "$run_createdb_result"
}
