package MediaWords::TM;

# General topic mapper utilities

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;
use Data::Dumper;

# get a list topics that match the topic option, which can either be an id
# or a pattern that matches topic names. Die if no topics are found.
sub require_topics_by_opt
{
    my ( $db, $topic_opt ) = @_;

    if ( !defined( $topic_opt ) )
    {
        Getopt::Long::GetOptions( "topic=s" => \$topic_opt ) || return;
    }

    die( "Usage: $0 --topic < id or pattern >" ) unless ( $topic_opt );

    my $topics;
    if ( $topic_opt =~ /^\d+$/ )
    {
        $topics = $db->query( "select * from topics where topics_id = ?", $topic_opt )->hashes;
        die( "No topics found by id '$topic_opt'" ) unless ( @{ $topics } );
    }
    else
    {
        $topics = $db->query( "select * from topics where name ~* ?", '^' . $topic_opt . '$' )->hashes;
        die( "No topics found by pattern '$topic_opt'" ) unless ( @{ $topics } );
    }

    return $topics;
}

sub get_latest_overall_timespan
{
    my ( $db, $topics_id ) = @_;

    my $timespan = $db->query( <<SQL, $topics_id )->hash;
select *
   from timespans timespan
       join snapshots snap on ( snap.snapshots_id = timespan.snapshots_id )
   where
       snap.topics_id = \$1 and
       timespan.period = 'overall'
   order by snap.snapshot_date desc
SQL

    return $timespan;
}

sub _get_timespan
{
    my ( $db, $timespans_id ) = @_;

    my $timespan = $db->query( <<SQL, $timespans_id )->hash;
select *, snap.topics_id
from timespans timespan
join snapshots snap on (snap.snapshots_id = timespan.snapshots_id)
where
  timespan.timespans_id = \$1
SQL
    unless ( $timespan )
    {
        LOGDIE( "no timespan for timespan $timespans_id" );
    }
}

sub _get_overall_timespan_from_snapshot
{
    my ( $db, $snapshot ) = @_;

    my $timespan = $db->query( <<SQL, $snapshot )->hash;
select *, snap.topics_id
  from timespans timespan
  join snapshots snap on (snap.snapshots_id = timespan.snapshots_id)
  where
    timespan.snapshots_id = \$1 and
    timespan.period = 'overall' and
    timespan.foci_id is null
SQL
    unless ( $timespan )
    {
        LOGDIE( "no overall timespan for snapshot $snapshot" );
    }
}

sub _get_latest_overall_timespan_from_topic
{
    my ( $db, $topics_id ) = @_;
    my $timespan = $db->query( <<SQL, $topics_id )->hash;
select *, snap.topics_id
  from timespans timespan
  join snapshots snap on (snap.snapshots_id = timespan.snapshots_id)
  where
    snap.topics_id = \$1 and
    timespan.period = 'overall' and
    timespan.foci_id is null
  order by snap.snapshot_date desc limit 1
SQL
}

# return in order of preference:
# * timespan if timespan specified
# * latest timespan of snapshot is specified
# * latest overall timespan
sub get_timespan_for_topic
{
    my ( $db, $topics_id, $timespans_id, $snapshot ) = @_;

    my $timespan = $timespans_id && _get_timespan( $db, $timespans_id );

    return $timespan if ( $timespan );

    $timespan = $snapshot && _get_overall_timespan_from_snapshot( $db, $snapshot );

    return $timespan if ( $timespan );

    return _get_latest_overall_timespan_from_topic( $db, $topics_id );

    return $timespan;
}

# call a get_timespan_for_contoversy; die if no timespan can be found.
sub require_timespan_for_topic
{
    my ( $db, $topics_id, $timespans_id, $snapshot ) = @_;

    my $timespan = get_timespan_for_topic( $db, $topics_id, $timespans_id, $snapshot );

    die( "Unable to find timespan for topic, timespan, or snapshot" ) unless ( $timespan );

    return $timespan;
}

1;
