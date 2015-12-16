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
use MediaWords::GearmanFunction::Bitly::EnqueueStory;

use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $stories = $db->query(
        <<EOF
        SELECT stories_id
        FROM stories
        ORDER BY stories_id
EOF
    )->hashes;

    foreach my $story ( @{ $stories } )
    {
        my $stories_id = $story->{ stories_id };

        say STDERR "Enqueueing story $stories_id...";
        MediaWords::GearmanFunction::Bitly::EnqueueStory->enqueue_on_gearman( { stories_id => $stories_id } );
    }
}

main();
