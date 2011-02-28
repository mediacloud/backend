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

# start a daemon that checks periodically for new vectors to update by finding one of:
# * a media_set with vectors_added == false
# * a dashboard with vectors_added == false
# * yesterday has no aggregate data
sub run_daemon
{
    my ( $db ) = @_;

    while ( 1 )
    {
        my ( $yesterday ) = $db->query( "select date_trunc( 'day', now() - interval '12 hours' )" )->flat;
        my ( $one_month_ago ) = $db->query( "select date_trunc( 'day', now() - interval '1 month' )" )->flat;
        ( $yesterday, $one_month_ago ) = map { substr( $_, 0, 10 ) } ( $yesterday, $one_month_ago );

        MediaWords::StoryVectors::update_aggregate_words( $db, $one_month_ago, $yesterday );

        # this is almost as slow as just revectoring everthing, so I'm commenting out for now
        my $media_sets = $db->query( "select ms.* from media_sets ms where ms.vectors_added = false order by ms.media_sets_id" )->hashes;
        for my $media_set ( @{ $media_sets } )
        {
            my ( $start_date, $end_date ) = get_media_set_date_range( $db, $media_set );
            if ( $start_date && $end_date )
            {
                print STDERR "update_aggregate_vectors: media_set $media_set->{ media_sets_id }\n";
                MediaWords::StoryVectors::update_aggregate_words( 
                    $db, $start_date, $end_date, 0, undef, $media_set->{ media_sets_id } ); 
                $db->query( "update media_sets set vectors_added = true where media_sets_id = ?", $media_set->{ media_sets_id } );
            }
        }

        my $dashboard_topics = $db->query( "select * from dashboard_topics where vectors_added = false order by dashboard_topics_id" )->hashes;
        for my $dashboard_topic ( @{ $dashboard_topics } )
        {
            print STDERR "update_aggregate_vectors: dashboard_topic $dashboard_topic->{ dashboard_topics_id }\n";

            my ( $start_date, $end_date ) = map { substr( $_, 0, 10 ) } 
                ( $dashboard_topic->{ start_date } , $dashboard_topic->{ end_date } );
            if ( $end_date gt $yesterday ) 
            {
                $end_date = $yesterday;
            }
            
            MediaWords::StoryVectors::update_aggregate_words(
                $db, $start_date, $end_date, 0, $dashboard_topic->{ dashboard_topics_id } );

            $db->query( "update dashboard_topics set vectors_added = true where dashboard_topics_id = ?",
                $dashboard_topic->{ dashboard_topics_id } );
        }

        sleep( 60 );
    }
}

sub main
{
    my $top_500_only = @ARGV && ( $ARGV[0] eq '-5' ) && shift( @ARGV );
    my $daemon       = @ARGV && ( $ARGV[0] eq '-d' ) && shift( @ARGV );
    my $force        = @ARGV && ( $ARGV[0] eq '-f' ) && shift( @ARGV );

    my ( $start_date, $end_date ) = @ARGV;

    if (   ( $start_date && !( $start_date =~ /^[0-9]{4,4}-[0-9]{2,2}-[0-9]{2,2}$/ ) )
        || ( $end_date && !( $end_date =~ /^[0-9]{4,4}-[0-9]{2,2}-[0-9]{2,2}$/ ) ) )
    {
        die( "date must be in the format YYYY-MM-DD" );
    }

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    if ( $top_500_only )
    {
        MediaWords::StoryVectors::_update_top_500_weekly_words( $db, $start_date );
        $db->commit;
    }
    elsif ( $daemon )
    {
        run_daemon( $db );
    }
    else
    {
        MediaWords::StoryVectors::update_aggregate_words( $db, $start_date, $end_date, $force );
    }
}

main();
