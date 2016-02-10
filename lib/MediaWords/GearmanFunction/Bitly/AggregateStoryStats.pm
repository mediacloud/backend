package MediaWords::GearmanFunction::Bitly::AggregateStoryStats;

#
# Use story's click counts to fill up aggregated stats table
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/Bitly/AggregateStoryStats.pm
#

use strict;
use warnings;

use Moose;

# Don't log each and every extraction job into the database
with 'Gearman::JobScheduler::AbstractFunction';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::GearmanJobSchedulerConfiguration;
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

    # Postpone connecting to the database so that compile test doesn't do that
    $db ||= MediaWords::DB::connect_to_db();

    my $stories_id = $args->{ stories_id } or die "'stories_id' is not set.";

    say STDERR "Aggregating story stats for story $stories_id...";

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story )
    {
        die "Unable to find story $stories_id.";
    }

    my $stats = MediaWords::Util::Bitly::read_story_stats( $db, $stories_id );
    unless ( defined $stats )
    {
        die "Stats for story $stories_id is undefined; perhaps story is not (yet) processed with Bit.ly?";
    }
    unless ( ref( $stats ) eq ref( {} ) )
    {
        die "Stats for story $stories_id is not a hashref.";
    }

    my $agg_stats = MediaWords::Util::Bitly::aggregate_story_stats( $stories_id, $story->{ url }, $stats );

    my $total_click_count = $agg_stats->total_click_count();
    say STDERR "Story's $stories_id total click count: $total_click_count";

    $db->query(
        <<EOF,
        SELECT upsert_bitly_clicks_total(?, ?)
EOF
        $stories_id, $total_click_count
    );

    say STDERR "Done aggregating story stats for story $stories_id.";
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
