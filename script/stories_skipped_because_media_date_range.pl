#!/usr/bin/env perl
#
# Reextract (and selectively reannotate with CoreNLP) stories that were skipped
# because of media.sw_data_start_date, media.sw_data_end_date and related code
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
use Data::Dumper;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    Readonly my $CHUNK_SIZE => 1000;

    DEBUG "Adding stories to extractor queue...";
    my $stories_to_reextract;
    do
    {
        DEBUG "Fetching chunk of up to $CHUNK_SIZE stories to extract...";

        $db->begin_work;

        $stories_to_reextract = $db->query(
            <<EOF,
                SELECT stories_id
                FROM scratch.stories_skipped_because_media_date_range
                ORDER BY stories_id
                LIMIT ?
EOF
            $CHUNK_SIZE
        )->hashes;

        if ( scalar( @{ $stories_to_reextract } ) > 0 )
        {
            DEBUG "Adding " . scalar( @{ $stories_to_reextract } ) . " stories...";

            foreach my $story_to_reextract ( @{ $stories_to_reextract } )
            {
                my $stories_id = $story_to_reextract->{ stories_id };

                my $args = {
                    stories_id                             => $stories_id,

                    # Doesn't influence job extraction in any way, used for
                    # easier grepping
                    story_skipped_because_media_date_range => 1,

                    # Story got extracted fine (it's just sentence extraction
                    # that was skipped) so it should have been added to Bit.ly
                    # schedule already
                    skip_bitly_processing => 1,
                };

                if ( $stories_id <= 29_000_000 )
                {
                    # It is likely that story didn't come up with any sentences
                    # so (re)add it to CoreNLP queue
                    $args->{ skip_corenlp_annotation } = 1;
                }

                DEBUG "Adding story $stories_id to extractor queue...";
                DEBUG "(Arguments for story $stories_id: " . Dumper( $args );

                my $priority = $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_LOW;
                MediaWords::Job::ExtractAndVector->add_to_queue( $args, $priority );

                $db->query(
                    <<EOF,
                    DELETE FROM scratch.stories_skipped_because_media_date_range
                    WHERE stories_id = ?
EOF
                    $stories_id
                );
            }

            DEBUG "Added " . scalar( @{ $stories_to_reextract } ) . " stories.";
        }
        else
        {
            DEBUG "No more stories left to extract.";
        }

        $db->commit;

    } until ( scalar( @{ $stories_to_reextract } ) == 0 );

    DEBUG "Done adding stories to extractor queue.";
}

main();

# Required by Sys::RunAlone
__END__
