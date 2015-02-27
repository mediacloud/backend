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
    my $story_batch_size          = 10;
    my $gearman_queue_limit       = 8;
    my $sleep_time                = 20;

    my $gearman_db = MediaWords::DB::connect_to_db( "gearman" );

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
            sleep 20;
            next;
        }

        my $rows = $db->query(
"select ps.* from processed_stories ps where processed_stories_id > ? EXCEPT select ps.* from processed_stories ps, stories_tags_map stm where ps.stories_id = stm.stories_id AND processed_stories_id > ? AND tags_id = ? order by processed_stories_id asc limit ? ",
            $last_processed_stories_id, $last_processed_stories_id, $tags_id, $story_batch_size )->hashes;

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

    }
}

main();
