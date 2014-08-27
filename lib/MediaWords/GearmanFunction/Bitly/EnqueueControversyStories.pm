package MediaWords::GearmanFunction::Bitly::EnqueueControversyStories;

#
# Enqueue all controversy's stories for processing via Bit.ly API
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/Bitly/EnqueueControversyStories.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::GearmanFunction';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::Bitly;
use MediaWords::GearmanFunction::Bitly::FetchStoryStats;
use Readonly;
use DateTime;

# Having a global database object should be safe because
# Gearman::JobScheduler's workers don't support fork()s anymore
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
    my $do_not_overwrite = $args->{ do_not_overwrite } // 0;

    say STDERR "Will enqueue all controversy's $controversies_id stories.";
    if ( $do_not_overwrite )
    {
        say STDERR "Will *not* overwrite stories that are already processed with Bit.ly";
    }
    else
    {
        say STDERR "Will overwrite stories that are already processed with Bit.ly";
    }

    say STDERR "Fetching controversy $controversies_id...";
    my $controversy = $db->find_by_id( 'controversies', $controversies_id );
    unless ( $controversy )
    {
        die "Controversy $controversies_id was not found";
    }
    say STDERR "Done fetching controversy $controversies_id.";

    unless ( $controversy->{ process_with_bitly } )
    {
        die "Controversy $controversies_id is not set up for Bit.ly processing; please set controversies.process_with_bitly";
    }

    say STDERR "Fetching controversy's $controversies_id start and end timestamps...";
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

    say STDERR "Start timestamp: " . DateTime->from_epoch( epoch => $start_timestamp )->ymd();
    say STDERR "End timestamp: " . DateTime->from_epoch( epoch => $end_timestamp )->ymd();

    say STDERR "Done fetching controversy's $controversies_id start and end timestamps.";

    say STDERR "Enqueueing controversy's $controversies_id stories for Bit.ly processing...";

    Readonly my $CHUNK_SIZE => 100;

    my $stories                       = [ 'non-empty array' ];
    my $offset_controversy_stories_id = 0;
    while ( scalar( @{ $stories } ) > 0 )    # while there are no more downloads
    {
        say STDERR "Fetching chunk of stories with 'controversy_stories_id' offset $offset_controversy_stories_id...";

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
        say STDERR "Done fetching chunk of stories with 'controversy_stories_id' offset $offset_controversy_stories_id.";

        say STDERR "Number of stories in a chunk: " . scalar( @{ $stories } );

        last unless ( scalar( @{ $stories } ) > 0 );    # no more stories

        foreach my $story ( @{ $stories } )
        {

            my $controversy_stories_id = $story->{ controversy_stories_id };
            my $stories_id             = $story->{ stories_id };

            $offset_controversy_stories_id = $controversy_stories_id;

            if ( MediaWords::Util::Bitly::story_is_processed( $db, $stories_id ) )
            {
                if ( $do_not_overwrite )
                {
                    say STDERR "Story $stories_id for controversy $controversies_id is already " .
                      "processed with Bit.ly, skipping.";
                    next;
                }
                else
                {
                    say STDERR "Story $stories_id for controversy $controversies_id is already " .
                      "processed with Bit.ly, will overwrite.";
                }
            }

            say STDERR "Enqueueing story $stories_id for Bit.ly processing...";

            my $args = {
                stories_id      => $stories_id,
                start_timestamp => $start_timestamp,
                end_timestamp   => $end_timestamp
            };
            MediaWords::GearmanFunction::Bitly::FetchStoryStats->enqueue_on_gearman( $args );

            say STDERR "Done enqueueing story $stories_id for Bit.ly processing.";
        }

        say STDERR "Will fetch another chunk of stories for controversy $controversies_id.";
    }

    say STDERR "Done enqueueing controversy's $controversies_id stories for Bit.ly processing.";
}

# write a single log because there are a lot of Bit.ly processing jobs so it's
# impractical to log each job into a separate file
sub unify_logs()
{
    return 1;
}

# (Gearman::JobScheduler::AbstractFunction implementation) Return default configuration
sub configuration()
{
    return MediaWords::Util::GearmanJobSchedulerConfiguration->instance;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
