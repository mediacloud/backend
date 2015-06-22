#!/usr/bin/env perl
#
# Enqueue stories from "extra_corenlp_stories" for CoreNLP processing.
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
use MediaWords::Util::CoreNLP;
use MediaWords::GearmanFunction::AnnotateWithCoreNLP;

use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    unless ( MediaWords::Util::CoreNLP::annotator_is_enabled() )
    {
        die "CoreNLP annotator is not enabled in the configuration.";
    }

    my $stories = $db->query(
        <<EOF
        SELECT stories_id
        FROM extra_corenlp_stories
        ORDER BY extra_corenlp_stories_id
EOF
    )->hashes;

    say STDERR "Will attempt to enqueue " . scalar( @{ $stories } ) . " stories.";

    my $stories_enqueued = 0;
    foreach my $story ( @{ $stories } )
    {
        my $stories_id = $story->{ stories_id };

        if ( MediaWords::Util::CoreNLP::story_is_annotated( $db, $stories_id ) )
        {
            say STDERR "Story $stories_id is already annotated with CoreNLP";
            next;
        }

        unless ( MediaWords::Util::CoreNLP::story_is_annotatable( $db, $stories_id ) )
        {
            say STDERR "Story $stories_id is not annotatable with CoreNLP.";
            next;
        }

        say STDERR "Enqueueing story $stories_id...";
        MediaWords::GearmanFunction::AnnotateWithCoreNLP->enqueue_on_gearman( { stories_id => $stories_id } );
        ++$stories_enqueued;
    }

    say STDERR "Done enqueuing $stories_enqueued stories.";
}

main();
