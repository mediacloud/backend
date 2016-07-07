#!/usr/bin/env perl
#
# Add stories from "stories_from_failed_bitly_rabbitmq_queue" table to
# the Bit.ly processing schedule
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
use MediaWords::Util::Bitly::Schedule;

use Sys::RunAlone;

use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    Readonly my $CHUNK_SIZE => 1000;

    DEBUG "Adding stories to Bit.ly schedule...";
    my $stories_to_add;
    do
    {
        DEBUG "Fetching chunk of up to $CHUNK_SIZE stories to add...";

        $db->begin_work;

        $stories_to_add = $db->query(
            <<EOF,
                SELECT stories_id
                FROM stories_from_failed_bitly_rabbitmq_queue
                ORDER BY stories_id
                LIMIT ?
EOF
            $CHUNK_SIZE
        )->hashes;

        if ( scalar( @{ $stories_to_add } ) > 0 )
        {
            DEBUG "Adding " . scalar( @{ $stories_to_add } ) . " stories...";

            foreach my $story ( @{ $stories_to_add } )
            {
                my $stories_id = $story->{ stories_id };

                DEBUG "Adding story $stories_id to Bit.ly schedule...";
                MediaWords::Util::Bitly::Schedule::add_to_processing_schedule( $db, $stories_id );

                $db->query(
                    <<EOF,
                    DELETE FROM stories_from_failed_bitly_rabbitmq_queue
                    WHERE stories_id = ?
EOF
                    $stories_id
                );
            }

            DEBUG "Added " . scalar( @{ $stories_to_add } ) . " stories.";
        }
        else
        {
            DEBUG "No more stories left to add.";
        }

        $db->commit;

    } until ( scalar( @{ $stories_to_add } ) == 0 );

    DEBUG "Done adding stories to Bit.ly schedule.";
}

main();

# Required by Sys::RunAlone
__END__
