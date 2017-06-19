package MediaWords::Job::Bitly::AggregateStoryStats;

#
# Use story's click counts to fill up aggregated stats table
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/mjm_worker.pl lib/MediaWords/Job/Bitly/AggregateStoryStats.pm
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
use Readonly;
use Data::Dumper;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    my $stories_id = $args->{ stories_id } or die "'stories_id' is not set.";

    INFO "Aggregating story stats for story $stories_id...";

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
    INFO "Story's $stories_id total click count: $total_click_count";

    $db->query(
        <<SQL,
        -- bitly_clicks_total_partition_by_stories_id_insert_trigger() trigger will do an upsert
        INSERT INTO bitly_clicks_total (stories_id, click_count)
        VALUES (?, ?)
SQL
        $stories_id, $total_click_count
    );

    INFO "Adding story $stories_id to Solr (re)import queue...";
    $db->query(
        <<EOF,
        INSERT INTO solr_import_extra_stories (stories_id)
        VALUES (?)
EOF
        $stories_id
    );

    INFO "Done aggregating story stats for story $stories_id.";
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
