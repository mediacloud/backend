package MediaWords::CM;

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
       join snapshots cd on ( cd.snapshots_id = timespan.snapshots_id )
   where
       cd.topics_id = \$1 and
       timespan.period = 'overall'
   order by cd.snapshot_date desc
SQL

    return $timespan;
}

sub _get_timespan
{
    my ( $db, $timespan ) = @_;

    my $timespan = $db->query( <<SQL, $timespan )->hash;
select *, cd.topics_id
from timespans timespan
join snapshots cd on (cd.snapshots_id = timespan.snapshots_id)
where
  timespan.timespans_id = \$1
SQL
    unless ( $timespan )
    {
        LOGDIE( "no timespan for timespan $timespan" );
    }
}

sub _get_overall_timespan_from_snapshot
{
    my ( $db, $snapshot ) = @_;

    my $timespan = $db->query( <<SQL, $snapshot )->hash;
select *, cd.topics_id
  from timespans timespan
  join snapshots cd on (cd.snapshots_id = timespan.snapshots_id)
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
select *, cd.topics_id
  from timespans timespan
  join snapshots cd on (cd.snapshots_id = timespan.snapshots_id)
  where
    cd.topics_id = \$1 and
    timespan.period = 'overall' and
    timespan.foci_id is null
  order by cd.snapshot_date desc limit 1
SQL
}

# return in order of preference:
# * timespan if timespan specified
# * latest timespan of snapshot is specified
# * latest overall timespan
sub get_timespan_for_topic
{
    my ( $db, $topics_id, $timespan, $snapshot ) = @_;

    my $timespan = $timespan && _get_timespan( $db, $timespan );

    return $timespan if ( $timespan );

    $timespan = $snapshot && _get_overall_timespan_from_snapshot( $db, $snapshot );

    return $timespan if ( $timespan );

    return _get_latest_overall_timespan_from_topic( $db, $topics_id );

    return $timespan;
}

# call a get_timespan_for_contoversy; die if no timespan can be found.
sub require_timespan_for_topic
{
    my ( $db, $topics_id, $timespan, $snapshot ) = @_;

    my $timespan = get_timespan_for_topic( $db, $topics_id, $timespan, $snapshot );

    die( "Unable to find timespan for topic, timespan, or snapshot" ) unless ( $timespan );

    return $timespan;
}

1;
