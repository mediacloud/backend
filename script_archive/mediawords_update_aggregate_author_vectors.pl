#!/usr/bin/perl

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
use MediaWords::StoryVectors;

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
            $media_set->{ media_sets_id } )->flat;
    } 
    elsif ( $media_set->{ set_type } eq 'medium' ) {
        ( $start_date, $end_date ) = $db->query(
            "select min(d.start_date), max(d.end_date) " . 
            "  from dashboard_media_sets dms, dashboards d, media_sets_media_map msmm, media_sets ms " . 
            "  where dms.dashboards_id = d.dashboards_id and dms.media_sets_id = msmm.media_sets_id and " .
            "  msmm.media_id = ms.media_id and ms.media_sets_id = ?", 
            $media_set->{ media_sets_id } )->flat;
    }
    elsif ( $media_set->{ set_type } eq 'cluster' ) {
        ( $start_date, $end_date ) = $db->query(
            "select min(d.start_date), max(d.end_date) " . 
            "  from dashboard_media_sets dms, dashboards d, media_clusters mc, media_sets ms " .
            "  where ms.media_sets_id = ? and ms.media_clusters_id = mc.media_clusters_id and " .
            "    mc.media_cluster_runs_id = dms.media_cluster_runs_id and " . 
            "    dms.dashboards_id = d.dashboards_id",
            $media_set->{ media_sets_id } )->flat;        
    }
    else {
        die( "unknown set_type '$media_set->{ set_type }'" );
    }
    
    ( $start_date, $end_date ) = map { substr( $_, 0, 10 ) } ( $start_date, $end_date );
    
    return ( $start_date, $end_date );
}

sub main
{
    my $force        = @ARGV && ( $ARGV[0] eq '-f' ) && shift( @ARGV );

    my ( $start_date, $end_date ) = @ARGV;

    if (   ( $start_date && !( $start_date =~ /^[0-9]{4,4}-[0-9]{2,2}-[0-9]{2,2}$/ ) )
        || ( $end_date && !( $end_date =~ /^[0-9]{4,4}-[0-9]{2,2}-[0-9]{2,2}$/ ) ) )
    {
        die( "date must be in the format YYYY-MM-DD" );
    }

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    {
        MediaWords::StoryVectors::update_aggregate_author_words( $db, $start_date, $end_date, $force );
    }
}

main();
