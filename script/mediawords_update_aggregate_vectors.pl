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

# get the min start_date and max end_date for the dashboards associated with the given
# media set
sub get_media_set_date_range
{
    my ( $db, $media_set ) = @_;

    my ( $start_date, $end_date );
    if ( $media_set->{ set_type } eq 'collection' )
    {
        ( $start_date, $end_date ) = $db->query(
            <<"EOF",
            SELECT MIN(d.start_date),
                   MAX(d.end_date)
            FROM dashboard_media_sets AS dms,
                 dashboards AS d
            WHERE dms.dashboards_id = d.dashboards_id
                  AND dms.media_sets_id = ?
EOF
            $media_set->{ media_sets_id }
        )->flat;
    }
    elsif ( $media_set->{ set_type } eq 'medium' )
    {
        ( $start_date, $end_date ) = $db->query(
            <<"EOF",
            SELECT MIN(d.start_date),
                   MAX(d.end_date)
            FROM dashboard_media_sets AS dms,
                 dashboards AS d,
                 media_sets_media_map AS msmm,
                 media_sets AS ms
            WHERE dms.dashboards_id = d.dashboards_id
                  AND dms.media_sets_id = msmm.media_sets_id
                  AND msmm.media_id = ms.media_id
                  AND ms.media_sets_id = ?
EOF
            $media_set->{ media_sets_id }
        )->flat;
    }
    elsif ( $media_set->{ set_type } eq 'cluster' )
    {
        ( $start_date, $end_date ) = $db->query(
            <<"EOF",
            SELECT MIN(d.start_date),
                   MAX(d.end_date)
            FROM dashboard_media_sets AS dms,
                 dashboards AS d,
                 media_clusters AS mc,
                 media_sets AS ms
            WHERE ms.media_sets_id = ?
                  AND ms.media_clusters_id = mc.media_clusters_id
                  AND mc.media_cluster_runs_id = dms.media_cluster_runs_id
                  AND dms.dashboards_id = d.dashboards_id
EOF
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
    my ( $db ) = @_;

    while ( 1 )
    {
        my ( $yesterday ) = $db->query( "SELECT DATE_TRUNC( 'day', NOW() - INTERVAL '12 hours' )::date" )->flat;

        my ( $one_month_ago ) = $db->query( "SELECT DATE_TRUNC( 'day', NOW() - INTERVAL '1 month' )::date" )->flat;
        ( $yesterday, $one_month_ago ) = map { substr( $_, 0, 10 ) } ( $yesterday, $one_month_ago );

        MediaWords::StoryVectors::update_aggregate_words( $db, $one_month_ago, $yesterday );

        # this is almost as slow as just revectoring everthing, so I'm commenting out for now
        my $media_sets = $db->query(
            <<"EOF"
            SELECT ms.*
            FROM media_sets AS ms
            WHERE ms.vectors_added = false
            ORDER BY ms.media_sets_id
EOF
        )->hashes;
        for my $media_set ( @{ $media_sets } )
        {
            my ( $start_date, $end_date ) = get_media_set_date_range( $db, $media_set );
            if ( $start_date && $end_date )
            {
                if ( $end_date gt $yesterday )
                {
                    $end_date = $yesterday;
                }

                print STDERR "update_aggregate_vectors: media_set $media_set->{ media_sets_id }\n";
                MediaWords::StoryVectors::update_aggregate_words( $db, $start_date, $end_date, 0, undef,
                    $media_set->{ media_sets_id } );
                $db->query( "UPDATE media_sets SET vectors_added = true WHERE media_sets_id = ?",
                    $media_set->{ media_sets_id } );
            }
        }

        my $pm               = new Parallel::ForkManager( 5 );
        my $dashboard_topics = $db->query(
            <<"EOF"
            SELECT *
            FROM dashboard_topics
            WHERE vectors_added = false
            ORDER BY dashboard_topics_id
EOF
        )->hashes;
        for my $dashboard_topic ( @{ $dashboard_topics } )
        {

            unless ( $pm->start )
            {
                print STDERR "update_aggregate_vectors: dashboard_topic $dashboard_topic->{ dashboard_topics_id }\n";

                my $db = MediaWords::DB::connect_to_db;

                my ( $start_date, $end_date ) =
                  map { substr( $_, 0, 10 ) } ( $dashboard_topic->{ start_date }, $dashboard_topic->{ end_date } );
                if ( $end_date gt $yesterday )
                {
                    $end_date = $yesterday;
                }

                MediaWords::StoryVectors::update_aggregate_words( $db, $start_date, $end_date, 1,
                    $dashboard_topic->{ dashboard_topics_id } );

                $db->query( "UPDATE dashboard_topics SET vectors_added = true WHERE dashboard_topics_id = ?",
                    $dashboard_topic->{ dashboard_topics_id } );

                $pm->finish;
            }
        }

        $pm->wait_all_children;

        sleep( 60 );
    }
}

sub main
{
    my $top_500_only = @ARGV && ( $ARGV[ 0 ] eq '-5' ) && shift( @ARGV );
    my $daemon       = @ARGV && ( $ARGV[ 0 ] eq '-d' ) && shift( @ARGV );
    my $force        = @ARGV && ( $ARGV[ 0 ] eq '-f' ) && shift( @ARGV );

    my ( $start_date, $end_date ) = @ARGV;

    die "date '$start_date' must be in the format YYYY-MM-DD"
      if $start_date && !( $start_date =~ /^[0-9]{4,4}-[0-9]{2,2}-[0-9]{2,2}$/ );
    die "date '$end_date' must be in the format YYYY-MM-DD"
      if $end_date && !( $end_date =~ /^[0-9]{4,4}-[0-9]{2,2}-[0-9]{2,2}$/ );

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
        MediaWords::DB::run_block_with_large_work_mem
        {
            MediaWords::StoryVectors::update_aggregate_words( $db, $start_date, $end_date, $force );
        }
        $db;
    }
}

main();
