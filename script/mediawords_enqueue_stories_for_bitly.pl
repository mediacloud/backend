#!/usr/bin/env perl
#
# Enqueue stories for Bit.ly processing
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
use MediaWords::DB;
use MediaWords::Util::Bitly;
use MediaWords::Util::Bitly::Schedule;
use MediaWords::GearmanFunction::Bitly::FetchStoryStats;

use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $db      = MediaWords::DB::connect_to_db;
    my $stories = $db->query(
        <<EOF
        SELECT *
        FROM stories
        ORDER BY stories_id
EOF
    )->hashes;

    foreach my $story ( @{ $stories } )
    {
        my $stories_id = $story->{ stories_id };

        my $story_timestamp = MediaWords::Util::Bitly::Schedule::story_timestamp( $stories_id );
        my $start_timestamp = MediaWords::Util::Bitly::Schedule::story_start_timestamp( $story_timestamp );
        my $end_timestamp   = MediaWords::Util::Bitly::Schedule::story_end_timestamp( $story_timestamp );

        say STDERR "Enqueueing story $stories_id...";
        MediaWords::GearmanFunction::Bitly::FetchStoryStats->enqueue_on_gearman(
            {
                stories_id      => $stories_id,
                start_timestamp => $start_timestamp,
                end_timestamp   => $end_timestamp
            }
        );
    }
}

main();
