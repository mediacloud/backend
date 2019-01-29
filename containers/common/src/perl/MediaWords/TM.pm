package MediaWords::TM;

# General topic mapper utilities

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;
use Data::Dumper;

use MediaWords::Util::Mail;

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
select timespan.*, snap.topics_id
   from timespans timespan
       join snapshots snap on ( snap.snapshots_id = timespan.snapshots_id )
   where
       snap.topics_id = \$1 and
       timespan.period = 'overall' and
       timespan.foci_id is null
   order by snap.snapshot_date desc
SQL

    return $timespan;
}

sub _get_timespan
{
    my ( $db, $timespans_id ) = @_;

    my $timespan = $db->query( <<SQL, $timespans_id )->hash;
select timespan.*, snap.topics_id
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
select timespan.*, snap.topics_id
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
select timespan.*, snap.topics_id
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
sub get_timespan_for_topic($$$$)
{
    my ( $db, $topics_id, $timespans_id, $snapshots_id ) = @_;

    $timespans_id ||= '';
    $snapshots_id ||= '';

    TRACE "get_timespan_for_topic: topics_id-$topics_id timespans_id-$timespans_id snapshots_id-$snapshots_id";

    my $timespan = $timespans_id && _get_timespan( $db, $timespans_id );

    return $timespan if ( $timespan );

    $timespan = $snapshots_id && _get_overall_timespan_from_snapshot( $db, $snapshots_id );

    return $timespan if ( $timespan );

    return _get_latest_overall_timespan_from_topic( $db, $topics_id );

    return $timespan;
}

# call a get_timespan_for_contoversy; die if no timespan can be found.
sub require_timespan_for_topic($$$$)
{
    my ( $db, $topics_id, $timespans_id, $snapshots_id ) = @_;

    my $timespan = get_timespan_for_topic( $db, $topics_id, $timespans_id, $snapshots_id );

    die( "Unable to find timespan for topic, timespan, or snapshot" ) unless ( $timespan );

    return $timespan;
}

# given a topics api request, call require_timespan_for_topic using the request topics_id, timespans_id, and
# snapshots_id, set the timespans_id parameter, and return the timespan
sub set_timespans_id_param($)
{
    my ( $c ) = @_;

    my $timespan = MediaWords::TM::require_timespan_for_topic(
        $c->dbis,
        $c->stash->{ topics_id },
        $c->req->params->{ timespans_id },
        $c->req->params->{ snapshots_id }
    );

    $c->req->params->{ timespans_id } = $timespan->{ timespans_id };

    return $timespan;
}

# send an alert about significant activity on the topic to all users with at least write access to the topic
sub send_topic_alert($$$)
{
    my ( $db, $topic, $message ) = @_;

    my $users = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select distinct au.*
    from auth_users au
        join topic_permissions tp using ( auth_users_id )
    where
        tp.permission in ( 'admin', 'write' ) and
        tp.topics_id = ?
SQL

    my $emails = [ map { $_->{ email } } @{ $users } ];

    if ( my $topic_alert_emails = MediaWords::Util::Config::get_config->{ mediawords }->{ topic_alert_emails } )
    {
        push( @{ $emails }, @{ $topic_alert_emails } );
    }

    my $emails_lookup = {};
    map { $emails_lookup->{ lc( $_ ) } = 1 } @{ $emails };
    $emails = [ keys( %{ $emails_lookup } ) ];

    for my $email ( @{ $emails } )
    {
        my $message = MediaWords::Util::Mail::Message::Templates::TopicSpiderUpdateMessage->new(
            {
                to                  => $email,
                topic_name          => $topic->{ name },
                topic_url           => "https://topics.mediacloud.org/#/topics/$topic->{ topics_id }/summary",
                topic_spider_status => $message,
            }
        );
        MediaWords::Util::Mail::send_email( $message );
    }

}

1;
