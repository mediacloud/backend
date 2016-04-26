package MediaWords::Job::Bitly::FetchStoryStats;

#
# Fetch story's click counts via Bit.ly API
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/Job/Bitly/FetchStoryStats.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::Bitly;
use MediaWords::Util::Bitly::API;
use MediaWords::Util::Process;
use MediaWords::Job::Bitly::AggregateStoryStats;
use Readonly;
use Data::Dumper;

# How many seconds to sleep between rate limiting errors
Readonly my $BITLY_RATE_LIMIT_SECONDS_TO_WAIT => 60 * 10;    # every 10 minutes

# How many times to try on rate limiting errors
Readonly my $BITLY_RATE_LIMIT_TRIES => 7;                    # try fetching 7 times in total (70 minutes)

# Having a global database object should be safe because
# job workers don't fork()
my $db = undef;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    # Postpone connecting to the database so that compile test doesn't do that
    $db ||= MediaWords::DB::connect_to_db();

    my $stories_id      = $args->{ stories_id } or die "'stories_id' is not set.";
    my $start_timestamp = $args->{ start_timestamp };
    my $end_timestamp   = $args->{ end_timestamp };

    my $now = time();
    unless ( $start_timestamp )
    {
        say STDERR "Start timestamp is not set, so I will use current timestamp $now as start date.";
        $start_timestamp = $now;
    }
    unless ( $end_timestamp )
    {
        say STDERR "End timestamp is not set, so I will use current timestamp $now as end date.";
        $end_timestamp = $now;
    }

    my $stats;
    my $retry = 0;
    my $error_message;
    do
    {
        say STDERR "Fetching story stats for story $stories_id" . ( $retry ? " (retry $retry)" : '' ) . "...";
        eval {
            $stats = MediaWords::Util::Bitly::fetch_stats_for_story( $db, $stories_id, $start_timestamp, $end_timestamp );
        };
        $error_message = $@;

        if ( $error_message )
        {
            if ( MediaWords::Util::Bitly::API::error_is_rate_limit_exceeded( $error_message ) )
            {

                say STDERR "Rate limit exceeded while collecting story stats for story $stories_id";
                say STDERR "Sleeping for $BITLY_RATE_LIMIT_SECONDS_TO_WAIT before retrying";

                sleep( $BITLY_RATE_LIMIT_SECONDS_TO_WAIT + 0 );

            }
            else
            {
                die "Error while collecting story stats for story $stories_id: $error_message";
            }
        }

        ++$retry;

    } until ( $retry > $BITLY_RATE_LIMIT_TRIES + 0 or ( !$error_message ) );

    unless ( $stats )
    {
        # No point die()ing and continuing with other jobs (didn't recover after rate limiting)
        fatal_error( "Stats for story ID $stories_id is undef (after $retry retries)." );
    }
    unless ( ref( $stats ) eq ref( {} ) )
    {
        # No point die()ing and continuing with other jobs (something wrong with fetch_stats_for_story())
        fatal_error( "Stats for story ID $stories_id is not a hashref." );
    }
    say STDERR "Done fetching story stats for story $stories_id.";

    # say STDERR "Stats: " . Dumper( $stats );

    say STDERR "Storing story stats for story $stories_id...";
    eval { MediaWords::Util::Bitly::write_story_stats( $db, $stories_id, $stats ); };
    if ( $@ )
    {
        # No point die()ing and continuing with other jobs (something wrong with the storage mechanism)
        fatal_error( "Error while storing story stats for story $stories_id: $@" );
    }
    say STDERR "Done storing story stats for story $stories_id.";

    # Enqueue aggregating Bit.ly stats
    MediaWords::Job::Bitly::AggregateStoryStats->add_to_queue( { stories_id => $stories_id } );
}

# write a single log because there are a lot of Bit.ly processing jobs so it's
# impractical to log each job into a separate file
sub unify_logs()
{
    return 1;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
