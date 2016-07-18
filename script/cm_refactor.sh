#!/bin/sh

cd ~hroberts/mediacloud

OPTS="--extensions pl,pm,yml,tt2,sql,t,markdown"
EXCLUDE="t/data/,lib/DBIx/Simple/MediaWords.pm,lib/MediaWords/Solr/Dump.pm,script/mediawords_generate_solr_dump.pl,script/mediawords_import_solr_data.pl"

DIRS="lib script root t doc"

function refactor {
    echo "REFACTOR $1 $2 $3 $4"

    if [[ -z "$4" ]]; then
        case="-i"
    else
        case=""
    fi

    codemod $OPTS --exclude-paths $EXCLUDE $case -d $1 "$2" "$3"
}

for DIR in $DIRS; do

    refactor $DIR cdts_id timespans_id
    refactor $DIR '(controversy_dump_time_slice|cdts)' timespan
    refactor $DIR 'Time Slice' Timespan y
    refactor $DIR 'time[ _]?slice' timespan
    refactor $DIR 'Controversy Dump' Snapshot y
    refactor $DIR 'controversy[ _]?dump' snapshot
    refactor $DIR 'dump_date' snapshot_date
    refactor $DIR '(controversy|topic)_query_slices' 'foci'
    refactor $DIR '(controversy|topic)_query_slice' 'focus'
    refactor $DIR 'Query Slices' 'Foci' y
    refactor $DIR 'query[ _]?slices' 'foci'
    refactor $DIR 'Query Slice' 'Focus' y
    refactor $DIR 'query[ _]?slice' 'focus'
    refactor $DIR 'Controvers(y|ie)' Topic y
    refactor $DIR 'controvers(y|ie)' topic
    refactor $DIR 'snapshots cd' 'snapshots snap'
    refactor $DIR 'cd\.' 'snap.'
    refactor $DIR 'cd_' 'snap_'
    refactor $DIR "'cd'" "'snap'"
    refactor $DIR 'CM::' 'TM::' y
    refactor $DIR 'CM;' 'TM;' y
    refactor $DIR 'CM/' 'TM/' y
    refactor $DIR '/cm/' '/tm/'
    refactor $DIR 'CM:' 'TM:' y
    refactor $DIR 'Dump(?!er)' 'Snapshot' y
    refactor $DIR 'dump(?!er|_terse)' 'snapshot' y

done
