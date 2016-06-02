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

    Readonly my $CHUNK_SIZE => 1000;

    DEBUG "Adding stories to reextractor queue...";
    my $stories_to_reextract;
    do
    {
        DEBUG "Fetching chunk of up to $CHUNK_SIZE stories to reextract...";

        $db->begin_work;

        $stories_to_reextract = $db->query(
            <<EOF,
                SELECT stories_id
                FROM stories_without_readability_tag
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

                DEBUG "Adding story $stories_id to reextractor queue...";
                MediaWords::Job::ExtractAndVector->add_to_queue( { stories_id => $stories_id },
                    $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_LOW );

                $db->query(
                    <<EOF,
                    DELETE FROM stories_without_readability_tag
                    WHERE stories_id = ?
EOF
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

    } until ( scalar( @{ $stories_to_reextract } ) == 0 );

    DEBUG "Done adding stories to reextractor queue.";
}

main();

# Required by Sys::RunAlone
__END__
