#!/usr/bin/env perl
#
# Add stories from "stories_without_readability_tag" table to the extractor queue
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::Job::ExtractAndVector;
use MediaCloud::JobManager::Job;

use Sys::RunAlone;

use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    Readonly my $CHUNK_SIZE => 10_000;

    # Wait a little between adding each chunk in order to not fill up job
    # broker's queue too quickly
    Readonly my $DELAY_BETWEEN_CHUNKS => 30;

    DEBUG "Adding stories to reextractor queue...";
    my $stories_to_reextract;
    do
    {
        DEBUG "Fetching chunk of up to $CHUNK_SIZE stories to reextract...";

        $db->begin_work;

        $stories_to_reextract = $db->query(
            <<SQL,
                SELECT stories_id
                FROM stories_without_readability_tag

                -- "UPDATE duplicates then INSERT non-duplicates to
                -- story_sentences" query adds an advisory lock on story's
                -- media_id. (Most?) stories (at least the old ones to be
                -- reextracted) got downloaded in chunks with the same media_id,
                -- so extractor has to wait for story's media_id to get
                -- unlocked and so can extract only a single story at a time.
                --
                -- Thus, randomize stories that are being fed into the queue
                -- for them to be reextracted in parallel without having to
                -- wait for locks.
                --
                -- This is going to run for ~60s but that's fine because we
                -- don't want to fill up RabbitMQ's queue too quickly anyway.
                ORDER BY RANDOM()

                LIMIT ?
SQL
            $CHUNK_SIZE
        )->hashes;

        if ( scalar( @{ $stories_to_reextract } ) > 0 )
        {
            DEBUG "Adding " . scalar( @{ $stories_to_reextract } ) . " stories...";

            foreach my $story_to_reextract ( @{ $stories_to_reextract } )
            {
                my $stories_id = $story_to_reextract->{ stories_id };

                DEBUG "Adding story $stories_id to reextractor queue...";
                my $args = {
                    stories_id              => $stories_id,
                    skip_bitly_processing   => 1,
                    skip_corenlp_annotation => 1,
                };
                my $priority = $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_LOW;
                MediaWords::Job::ExtractAndVector->add_to_queue( $args, $priority );

                $db->query(
                    <<SQL,
                    DELETE FROM stories_without_readability_tag
                    WHERE stories_id = ?
SQL
                    $stories_id
                );
            }

            DEBUG "Added " . scalar( @{ $stories_to_reextract } ) . " stories.";
        }
        else
        {
            DEBUG "No more stories left to reextract.";
        }

        $db->commit;

        INFO "Waiting $DELAY_BETWEEN_CHUNKS s...";
        sleep( $DELAY_BETWEEN_CHUNKS );

    } until ( scalar( @{ $stories_to_reextract } ) == 0 );

    DEBUG "Done adding stories to reextractor queue.";
}

main();

# Required by Sys::RunAlone
__END__
