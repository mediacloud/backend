package MediaWords::GearmanFunction::Bitly::AggregateStoryStats;

#
# Use story's click / referrer counts stored in GridFS to fill up aggregated stats table
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

    my $agg_stats      = MediaWords::Util::Bitly::aggregate_story_stats( $story, $stats );
    my $click_count    = $agg_stats->{ click_count };
    my $referrer_count = $agg_stats->{ referrer_count };

    say STDERR "Story's $stories_id click count: $click_count";
    say STDERR "Story's $stories_id referrer count: $referrer_count";

    # Store stats ("upsert" the record into "story_bitly_statistics" table)
    $db->query(
        <<EOF,
        SELECT upsert_story_bitly_statistics(?, ?, ?)
EOF
        $stories_id, $click_count, $referrer_count
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
