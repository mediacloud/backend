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

sub get_latest_overall_time_slice
{
    my ( $db, $topics_id ) = @_;

    my $cdts = $db->query( <<SQL, $topics_id )->hash;
select *
   from topic_dump_time_slices cdts
       join topic_dumps cd on ( cd.topic_dumps_id = cdts.topic_dumps_id )
   where
       cd.topics_id = \$1 and
       cdts.period = 'overall'
   order by cd.dump_date desc
SQL

    return $cdts;
}

sub _get_overall_time_slice_from_snapshot
{
    my ( $db, $snapshot ) = @_;

    my $cdts = $db->query( <<SQL, $snapshot )->hash;
select *
  from topic_dump_time_slices cdts
  where
    cdts.topic_dumps_id = \$1 and
    cdts.period = 'overall' and
    cdts.topic_query_slices_id is null
SQL
    unless ( $cdts )
    {
        LOGDIE( "no overall time slice for snapshot $snapshot" );
    }
}

sub _get_latest_overall_time_slice_from_topic
{
    my ( $db, $topics_id ) = @_;
    my $cdts = $db->query( <<SQL, $topics_id )->hash;
select *
  from topic_dump_time_slices cdts
  join topic_dumps cd on (cd.topic_dumps_id = cdts.topic_dumps_id)
  where
    cd.topics_id = \$1 and
    cdts.period = 'overall' and
    cdts.topic_query_slices_id is null
  order by cd.dump_date desc limit 1
SQL
}

# return in order of preference:
# * timeslice if timeslice specified
# * latest timeslice of snapshot is specified
# * latest overall timeslice
sub get_time_slice_for_topic
{
    my ( $db, $topics_id, $timeslice, $snapshot ) = @_;

    my $cdts = $db->find_by_id( 'topic_dump_time_slices', $timeslice );

    return $cdts if ( $cdts );

    $cdts = $snapshot && _get_overall_time_slice_from_snapshot( $db, $snapshot );

    return $cdts if ( $cdts );

    return _get_latest_overall_time_slice_from_topic( $db, $topics_id );

    return $cdts;
}

1;
