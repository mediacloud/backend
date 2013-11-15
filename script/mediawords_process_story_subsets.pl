#!/usr/bin/env perl

# update the aggregate vector tables needed to run clustering and dashboard systems
#
# requires a start date argument in '2009-10-01' format

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;
use Parallel::ForkManager;

use MediaWords::StoryVectors;
use MediaWords::DBI::StorySubsets;

# get the min start_date and max end_date for the dashboards associated with the given
# media set
sub get_media_set_date_range
{
    my ( $db, $media_set ) = @_;

    my ( $start_date, $end_date );
    if ( $media_set->{ set_type } eq 'collection' )
    {
        ( $start_date, $end_date ) = $db->query(
            "select min(d.start_date), max(d.end_date) from dashboard_media_sets dms, dashboards d " .
              "  where dms.dashboards_id = d.dashboards_id and dms.media_sets_id = ?",
            $media_set->{ media_sets_id }
        )->flat;
    }
    elsif ( $media_set->{ set_type } eq 'medium' )
    {
        ( $start_date, $end_date ) = $db->query(
            "select min(d.start_date), max(d.end_date) " .
              "  from dashboard_media_sets dms, dashboards d, media_sets_media_map msmm, media_sets ms " .
              "  where dms.dashboards_id = d.dashboards_id and dms.media_sets_id = msmm.media_sets_id and " .
              "  msmm.media_id = ms.media_id and ms.media_sets_id = ?",
            $media_set->{ media_sets_id }
        )->flat;
    }
    elsif ( $media_set->{ set_type } eq 'cluster' )
    {
        ( $start_date, $end_date ) = $db->query(
            "select min(d.start_date), max(d.end_date) " .
              "  from dashboard_media_sets dms, dashboards d, media_clusters mc, media_sets ms " .
              "  where ms.media_sets_id = ? and ms.media_clusters_id = mc.media_clusters_id and " .
              "    mc.media_cluster_runs_id = dms.media_cluster_runs_id and " . "    dms.dashboards_id = d.dashboards_id",
            $media_set->{ media_sets_id }
        )->flat;
    }
    else
    {
        die( "unknown set_type '$media_set->{ set_type }'" );
    }

    ( $start_date, $end_date ) = map { substr( $_, 0, 10 ) } ( $start_date, $end_date );

    return ( $start_date, $end_date );
}

# start a daemon that checks periodically for new vectors to update by finding one of:
# * a media_set with vectors_added == false
# * a dashboard with vectors_added == false
# * yesterday has no aggregate data
sub run_daemon
{
    while ( 1 )
    {

        my $pm = new Parallel::ForkManager( 1 );

        my $db = MediaWords::DB::connect_to_db;

        my $unprocessed_subsets =
          $db->query( "SELECT * FROM story_subsets WHERE not ready ORDER BY story_subsets_id ASC" )->hashes;

        for my $unprocessed_subset ( @{ $unprocessed_subsets } )
        {

            #unless ( $pm->start )
            {
                say STDERR "process_story_subset: $unprocessed_subset->{ story_subsets_id }";

                my $db = MediaWords::DB::connect_to_db;

                MediaWords::DBI::StorySubsets::process( $db, $unprocessed_subset );

                #   $pm->finish;
            }
        }

        # $pm->wait_all_children;

        say STDERR "Sleeping ... ";
        sleep( 60 );
    }
}

sub main
{
    run_daemon();
}

main();
