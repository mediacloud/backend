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
select timespan.*, snap.topics_id
   from timespans timespan
       join snapshots snap on ( snap.snapshots_id = timespan.snapshots_id )
   where
       snap.topics_id = ? and
       timespan.period = 'overall' and
       timespan.foci_id is null
   order by snap.snapshot_date desc
SQL

    return $timespan;
}


1;
