#!/bin/bash

if [ `uname` == 'Darwin' ]; then
    # Mac OS X
    PSQL=/usr/local/bin/psql
else
    # assume Ubuntu
    PSQL=psql
fi

read PGPASSWORD

FILE=$1

#echo PGHOST=$2 PGDATABASE=$3 PGUSER=$4 PGPASSWORD=$PGPASSWORD $PSQL -v 'ON_ERROR_STOP=on' --single-transaction -f "$FILE" 2>&1
PGHOST=$2 PGDATABASE=$3 PGUSER=$4 PGPASSWORD=$PGPASSWORD PGPORT=$5 \
	$PSQL -v 'ON_ERROR_STOP=on' --single-transaction -f "$FILE" 2>&1
if [ $? -ne 0 ]; then
	echo "$PSQL failed"
	exit 1
fi

exit 0
