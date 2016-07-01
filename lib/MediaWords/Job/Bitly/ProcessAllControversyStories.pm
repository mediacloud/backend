package MediaWords::Job::Bitly::ProcessAllControversyStories;

#
# Add all controversy stories to Bit.ly processing queue
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/mjm_worker.pl lib/MediaWords/Job/Bitly/ProcessAllControversyStories.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/mjm_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::Bitly;
use MediaWords::Util::DateTime;
use MediaWords::Job::Bitly::FetchStoryStats;
use Readonly;
use MediaCloud::JobManager::Job;

# Having a global database object should be safe because
# job workers don't fork()
my $db = undef;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    # Postpone connecting to the database so that compile test doesn't do that
    $db ||= MediaWords::DB::connect_to_db();

    my $controversies_id = $args->{ controversies_id } or die "'controversies_id' is not set.";

    DEBUG "Will add all controversy's $controversies_id stories.";

    DEBUG "Fetching controversy $controversies_id...";
    my $controversy = $db->find_by_id( 'controversies', $controversies_id );
    unless ( $controversy )
    {
        die "Controversy $controversies_id was not found";
    }
    DEBUG "Done fetching controversy $controversies_id.";

    DEBUG "Fetching controversy's $controversies_id start and end timestamps...";
    my $timestamps = $db->query(
        <<EOF,
        SELECT EXTRACT(EPOCH FROM MIN( start_date )::timestamp) AS start_timestamp,
               EXTRACT(EPOCH FROM MAX( end_date )::timestamp) AS end_timestamp
        FROM controversies_with_dates
        WHERE controversies_id = ?
EOF
        $controversies_id
    )->hash;
    unless ( $timestamps )
    {
        die "Unable to fetch controversy's start and end timestamps.";
    }
    my $start_timestamp = $timestamps->{ start_timestamp };
    my $end_timestamp   = $timestamps->{ end_timestamp };

    if ( $start_timestamp >= $end_timestamp )
    {
        die "Start timestamp ($start_timestamp) is bigger or equal to end timestamp ($end_timestamp).";
    }

    my $now = time();
    if ( $start_timestamp > $now )
    {
        DEBUG
"Start timestamp $start_timestamp is bigger than current timestamp $now, so worker will use current timestamp as start date.";
        $start_timestamp = undef;
    }
    else
    {
        DEBUG "Start timestamp: " . gmt_date_string_from_timestamp( $start_timestamp );
    }

    if ( $end_timestamp > $now )
    {
        DEBUG
"End timestamp $end_timestamp is bigger than current timestamp $now, so worker will use current timestamp as end date.";
        $end_timestamp = undef;
    }
    else
    {
        DEBUG "End timestamp: " . gmt_date_string_from_timestamp( $end_timestamp );
    }

    DEBUG "Done fetching controversy's $controversies_id start and end timestamps.";

    DEBUG "Adding controversy's $controversies_id stories to Bit.ly processing queue...";

    Readonly my $CHUNK_SIZE => 100;

    my $stories                       = [ 'non-empty array' ];
    my $offset_controversy_stories_id = 0;
    while ( scalar( @{ $stories } ) > 0 )    # while there are no more downloads
    {
        DEBUG "Fetching chunk of stories with 'controversy_stories_id' offset $offset_controversy_stories_id...";

        $stories = $db->query(
            <<"EOF",
            SELECT controversy_stories_id,
                   controversies_id,
                   stories_id
            FROM controversy_stories
            WHERE controversy_stories_id > ?
              AND controversies_id = ?
            ORDER BY controversy_stories_id
            LIMIT ?
EOF
            $offset_controversy_stories_id, $controversies_id, $CHUNK_SIZE
        )->hashes;
        DEBUG "Done fetching chunk of stories with 'controversy_stories_id' offset $offset_controversy_stories_id.";

        DEBUG "Number of stories in a chunk: " . scalar( @{ $stories } );

        last unless ( scalar( @{ $stories } ) > 0 );    # no more stories

        foreach my $story ( @{ $stories } )
        {

            my $controversy_stories_id = $story->{ controversy_stories_id };
            my $stories_id             = $story->{ stories_id };

            $offset_controversy_stories_id = $controversy_stories_id;

            DEBUG "Adding story $stories_id to Bit.ly processing queue...";

            my $args = {
                stories_id      => $stories_id,
                start_timestamp => $start_timestamp,
                end_timestamp   => $end_timestamp
            };

            # Bit.ly click counts for controversies are usually needed sooner
            # than the default background stats collection for all new stories
            my $priority = $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_HIGH;

            MediaWords::Job::Bitly::FetchStoryStats->add_to_queue( $args, $priority );

            DEBUG "Added story $stories_id to Bit.ly processing queue.";
        }

        DEBUG "Will fetch another chunk of stories for controversy $controversies_id.";
    }

    DEBUG "Added controversy's $controversies_id stories to Bit.ly processing queue.";
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
