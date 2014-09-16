package MediaWords::GearmanFunction::Bitly::FetchStoryStats;

#
# Fetch story's click / referrer count statistics via Bit.ly API
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/Bitly/FetchStoryStats.pm
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
use Readonly;
use Data::Dumper;

# Having a global database object should be safe because
# Gearman::JobScheduler's workers don't support fork()s anymore
my $db = undef;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    Readonly my $BITLY_FETCH_CATEGORIES => 0;
    Readonly my $BITLY_FETCH_CLICKS     => 1;
    Readonly my $BITLY_FETCH_REFERRERS  => 1;
    Readonly my $BITLY_FETCH_SHARES     => 0;

    Readonly my $stats_to_fetch => MediaWords::Util::Bitly::StatsToFetch->new(
        $BITLY_FETCH_CATEGORIES,    # "/v3/link/category"
        $BITLY_FETCH_CLICKS,        # "/v3/link/clicks"
        $BITLY_FETCH_REFERRERS,     # "/v3/link/referrers"
        $BITLY_FETCH_SHARES         # "/v3/link/shares"
    );

    # Postpone connecting to the database so that compile test doesn't do that
    $db ||= MediaWords::DB::connect_to_db();

    my $stories_id      = $args->{ stories_id }      or die "'stories_id' is not set.";
    my $start_timestamp = $args->{ start_timestamp } or die "'start_timestamp' is not set.";
    my $end_timestamp   = $args->{ end_timestamp }   or die "'end_timestamp' is not set.";

    say STDERR "Fetching story stats for story $stories_id...";

    my $stats =
      MediaWords::Util::Bitly::collect_story_stats( $db, $stories_id, $start_timestamp, $end_timestamp, $stats_to_fetch );
    unless ( ref( $stats ) eq ref( {} ) )
    {
        die "Stats for story ID $stories_id is not a hashref.";
    }
    say STDERR "Done fetching story stats for story $stories_id.";

    # say STDERR "Stats: " . Dumper( $stats );

    say STDERR "Storing story stats for story $stories_id...";
    MediaWords::Util::Bitly::write_story_stats( $db, $stories_id, $stats );
    say STDERR "Done storing story stats for story $stories_id.";
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
