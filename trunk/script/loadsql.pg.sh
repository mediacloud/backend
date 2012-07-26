#!/bin/sh

read PGPASSWORD
export PGPASSWORD

FILE=$1

PGHOST=$2
export PGHOST

PGDATABASE=$3
export PGDATABASE

PGUSER=$4
export PGUSER

psql  -v 'ON_ERROR_STOP=on' --single-transaction -f "$FILE"