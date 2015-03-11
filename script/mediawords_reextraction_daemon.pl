#!/usr/bin/env perl

#
# Enqueue MediaWords::GearmanFunction::ExtractAndVector jobs for all downloads
# in the scratch.reextract_downloads table
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";

use MediaWords::CommonLibs;
use MediaWords::GearmanFunction;
use MediaWords::GearmanFunction::ExtractAndVector;
use MediaWords::DBI::Stories;

sub main
{
    unless ( MediaWords::GearmanFunction::gearman_is_enabled() )
    {
        die "Gearman is disabled.";
    }

    my $db = MediaWords::DB::connect_to_db;

    my $tags_id = MediaWords::DBI::Stories::get_current_extractor_version_tags_id( $db );

    my $last_processed_stories_id = 0;
    my $story_batch_size          = 1000;
    my $gearman_queue_limit       = 200;
    my $sleep_time                = 20;

    my $gearman_db = MediaWords::DB::connect_to_db( "gearman" );

    my $total_stories_enqueued = 0;

    while ( 1 )
    {
        my $gearman_queued_jobs = $gearman_db->query(
            "SELECT count(*) from queue where function_name = 'MediaWords::GearmanFunction::ExtractAndVector' " )->flat()
          ->[ 0 ];

        say STDERR "Gearman queued jobs $gearman_queued_jobs";

        if ( $gearman_queued_jobs > $gearman_queue_limit )
        {
            say STDERR
"Gearman queue contains more then $gearman_queue_limit jobs ( $gearman_queued_jobs) sleeping $sleep_time seconds";
            sleep $sleep_time;
            next;
        }

        my $rows = $db->query(
"select ps.* from processed_stories ps left join  stories_tags_map stm on ( ps.stories_id=stm.stories_id and stm.tags_id=? ) where processed_stories_id > ? and tags_id is null order by processed_stories_id asc limit ?;",
            $tags_id, $last_processed_stories_id, $story_batch_size )->hashes;

        my $stories_ids = [ map { $_->{ stories_id } } @$rows ];

        last if scalar( @$stories_ids ) == 0;

        $last_processed_stories_id = $rows->[ -1 ]->{ processed_stories_id };

        my $i = 0;

        #say Dumper( $stories_ids );

        for my $stories_id ( @{ $stories_ids } )
        {
            MediaWords::GearmanFunction::ExtractAndVector->enqueue_on_gearman(
                { stories_id => $stories_id, disable_story_triggers => 1 } );

        }

        $total_stories_enqueued += scalar( @$stories_ids );

        say STDERR "last_processed_stories_id  $last_processed_stories_id ";
        say STDERR "total_stories_enqueued $total_stories_enqueued";
    }

    say STDERR "all stories extracted with readability";

}

main();
