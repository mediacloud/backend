#!/bin/sh

if [ `uname` == 'Darwin' ]; then
    # Mac OS X
    PSQL=/opt/local/lib/postgresql84/bin/psql
else
    # assume Ubuntu
    PSQL=psql
fi

read PGPASSWORD
export PGPASSWORD

FILE=$1

PGHOST=$2
export PGHOST

PGDATABASE=$3
export PGDATABASE

PGUSER=$4
export PGUSER

$PSQL  -v 'ON_ERROR_STOP=on' --single-transaction -f "$FILE"
