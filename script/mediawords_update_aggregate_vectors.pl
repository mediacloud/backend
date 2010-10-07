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

# start a daemon that checks periodically for new vectors to update by finding one of:
# * a media_set with vectors_added == false
# * a dashboard with vectors_added == false
# * yesterday has no aggregate data
sub run_daemon
{
    my ( $db ) = @_;

    while ( 1 )
    {
        my ( $yesterday ) = $db->query( "select date_trunc( 'day', now() - interval '36 hours' )" )->flat;
        my ( $one_month_ago ) = $db->query( "select date_trunc( 'day', now() - interval '1 month' )" )->flat;
        MediaWords::StoryVectors::update_aggregate_words( $db, $one_month_ago, $yesterday );

        # this is almost as slow as just revectoring everthing, so I'm commenting out for now
        my $media_sets = $db->query( "select ms.* from media_sets ms where ms.vectors_added = false" )->hashes;
        for my $media_set ( @{ $media_sets } )
        {
            my ( $start_date, $end_date ) = $db->query( 
                "select min(start_date), max(end_date) from dashboard_media_sets " . 
                "  where media_sets_id = ?", $media_set->{ media_sets_id } )->flat;
            print STDERR "update_aggregate_vectors: media_set $media_set->{ media_sets_id }\n";
            MediaWords::StoryVectors::update_aggregate_words( $db, $start_date, $end_date, 0, undef, $media_set->{ media_sets_id } );
            $db->query( "update media_sets set vectors_added = true where media_sets_id = ?", $media_set->{ media_sets_id } );
        }

        my $dashboard_topics = $db->query( "select * from dashboard_topics where vectors_added = false" )->hashes;
        for my $dashboard_topic ( @{ $dashboard_topics } )
        {
            print STDERR "update_aggregate_vectors: dashboard_topic $dashboard_topic->{ dashboard_topics_id }\n";

            $db->query( "update dashboard_topics set vectors_added = true where dashboard_topics_id = ?",
                $dashboard_topic->{ dashboard_topics_id } );

            MediaWords::StoryVectors::update_aggregate_words(
                $db,
                $dashboard_topic->{ start_date },
                $dashboard_topic->{ end_date },
                0, $dashboard_topic->{ dashboard_topics_id }
            );
        }

        sleep( 60 );
    }
}

sub main
{
    my $top_500_only = ( "$ARGV[0]" eq '-5' ) && shift( @ARGV );
    my $daemon       = ( "$ARGV[0]" eq '-d' ) && shift( @ARGV );
    my $force        = ( "$ARGV[0]" eq '-f' ) && shift( @ARGV );

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
