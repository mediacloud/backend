#!/usr/bin/env perl

#
# Add MediaWords::Job::ExtractAndVector job for every download in the scratch.reextract_downloads table
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";

use Time::HiRes qw (time );
use Parallel::ForkManager;

use MediaWords::CommonLibs;
use MediaWords::Job::ExtractAndVector;
use MediaWords::DBI::Stories;
use MediaWords::DBI::Stories::ExtractorVersion;

sub main
{
    my $tags_id =
      MediaWords::DBI::Stories::ExtractorVersion::get_current_extractor_version_tags_id( MediaWords::DB::connect_to_db() );

    my $story_batch_size    = 1000;
    my $gearman_queue_limit = 200;
    my $sleep_time          = 10;

    my $total_stories_added             = 0;
    my $total_gearman_add_to_queue_time = 0;
    my $total_story_query_time          = 0;

    MediaWords::DB::disable_story_triggers();

    my $start_time = Time::HiRes::time();

    my $total_sleep_time = 0;

    my $default_db_label = MediaWords::DB::connect_settings()->{ label };

    my $last_processed_stories_id;

    {
        my $db_tmp = MediaWords::DB::connect_to_db( $default_db_label );
        $last_processed_stories_id =
          $db_tmp->query( "SELECT max( processed_stories_id) from processed_stories" )->hashes()->[ 0 ]->{ max };

        say STDERR "last_processed_stories_id: $last_processed_stories_id";

    }

    while ( 1 )
    {
        my $gearman_db = MediaWords::DB::connect_to_db( "gearman" );
        my $db         = MediaWords::DB::connect_to_db( $default_db_label );

        say STDERR "Checking gearman queue";

        my $gearman_queued_jobs =
          $gearman_db->query( "SELECT count(*) from queue where function_name = 'MediaWords::Job::ExtractAndVector' " )
          ->flat()->[ 0 ];

        say STDERR "Gearman queued jobs $gearman_queued_jobs";

        if ( $gearman_queued_jobs > $gearman_queue_limit )
        {
            say STDERR
"Gearman queue contains more then $gearman_queue_limit jobs ( $gearman_queued_jobs) sleeping $sleep_time seconds";
            sleep $sleep_time;
            $total_sleep_time += $sleep_time;
            next;
        }

        say STDERR "last_processed_stories_id  $last_processed_stories_id ";

        my $query_start_time = Time::HiRes::time();

        my $rows = $db->query(
            <<"END_SQL",
        WITH  reextract_stories as (select ps.* from processed_stories ps left join  stories_tags_map stm on ( ps.stories_id=stm.stories_id and stm.tags_id=? ) where processed_stories_id < ? and tags_id is null order by processed_stories_id desc limit ?) select processed_stories_id, reextract_stories.stories_id from downloads, reextract_stories where downloads.stories_id = reextract_stories.stories_id and downloads.state not in ( 'error', 'fetching', 'pending', 'queued' ) and file_status <> 'missing' group by processed_stories_id, reextract_stories.stories_id order by processed_stories_id desc, reextract_stories.stories_id limit ?;
END_SQL
            $tags_id, $last_processed_stories_id, $story_batch_size * 3, $story_batch_size
        )->hashes;

        my $query_end_time = Time::HiRes::time();

        my $stories_ids = [ map { $_->{ stories_id } } @$rows ];

        if ( scalar( @$stories_ids ) == 0 )
        {
            say STDERR "No non-error stories found in batch. Checking for errored stories";
            my $processed_stories = $db->query(
                <<"END_SQL",
select ps.* from processed_stories ps left join stories_tags_map stm on ( ps.stories_id=stm.stories_id and stm.tags_id=? ) where processed_stories_id > ? and tags_id is null order by processed_stories_id asc limit ?
END_SQL
                $tags_id, $last_processed_stories_id, $story_batch_size * 3
            )->hashes();

            if ( scalar( @$processed_stories ) > 0 )
            {

                $last_processed_stories_id = $processed_stories->[ -1 ]->{ processed_stories_id };
                say STDERR "Setting processed_stories id to $last_processed_stories_id to move past download errors";
                next;
            }
            else
            {
                last;
            }
        }

        $last_processed_stories_id = $rows->[ -1 ]->{ processed_stories_id };

        my $i = 0;

        #say Dumper( $stories_ids );

        my $gearman_add_to_queue_start_time = Time::HiRes::time();

        my $pm = new Parallel::ForkManager( 20 );

        for my $stories_id ( @{ $stories_ids } )
        {
            unless ( $pm->start )
            {
                MediaWords::Job::ExtractAndVector->add_to_queue(
                    { stories_id => $stories_id, disable_story_triggers => 1 } );
                $pm->finish;
            }

        }

        $pm->wait_all_children;

        my $gearman_add_to_queue_end_time = Time::HiRes::time();

        my $stories_in_queue = scalar( @$stories_ids );
        $total_stories_added += $stories_in_queue;

        my $story_query_time = $query_end_time - $query_start_time;
        $total_story_query_time += $story_query_time;

        say STDERR "last_processed_stories_id  $last_processed_stories_id ";
        say STDERR "total_stories_added $total_stories_added";
        say STDERR "story_query_time $story_query_time";

        my $gearman_add_to_queue_time = $gearman_add_to_queue_end_time - $gearman_add_to_queue_start_time;
        $total_gearman_add_to_queue_time += $gearman_add_to_queue_time;

        my $total_time = Time::HiRes::time() - $start_time;

        my $total_other_time =
          $total_time - ( $total_gearman_add_to_queue_time + $total_story_query_time + $total_sleep_time );

        say STDERR "gearman_add_to_queue_time $gearman_add_to_queue_time for $stories_in_queue stories -- per story " .
          $gearman_add_to_queue_time / $stories_in_queue;

        say STDERR "total time $total_time for $total_stories_added stories -- per story " .
          $total_time / $total_stories_added;

        say STDERR
          "total gearman_add_to_queue_time $total_gearman_add_to_queue_time for $total_stories_added stories -- per story "
          . $total_gearman_add_to_queue_time / $total_stories_added;

        say STDERR "total story_query_time $total_story_query_time for $total_stories_added stories -- per story " .
          $total_story_query_time / $total_stories_added;

        say STDERR
          "total sleep time for long gearman queues $total_sleep_time for $total_stories_added stories -- per story " .
          $total_sleep_time / $total_stories_added;

        say STDERR "total time (other) $total_other_time for $total_stories_added stories -- per story " .
          $total_other_time / $total_stories_added;

    }

    say STDERR "all stories extracted with readability";

}

main();
