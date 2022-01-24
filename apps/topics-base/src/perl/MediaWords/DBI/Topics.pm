package MediaWords::DBI::Topics;

# General topic mapper utilities

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;


sub get_latest_overall_timespan
{
    my ( $db, $topics_id ) = @_;

    my $timespan = $db->query( <<SQL, $topics_id )->hash;
        SELECT timespans.*
        FROM timespans
            INNER JOIN snapshots ON
                timespans.topics_id = snapshots.topics_id AND
                timespans.snapshots_id = snapshots.snapshots_id
        WHERE
           timespans.topics_id = ? AND
           timespans.period = 'overall' AND
           timespans.foci_id IS NULL
        ORDER BY
            snapshots.snapshot_date DESC
SQL

    return $timespan;
}


1;
