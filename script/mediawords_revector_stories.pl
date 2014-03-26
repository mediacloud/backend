#!/usr/bin/env perl

# for every story in scratch.revector_stories, run update_story_sentences_and_languages and remove from
# scratch.revector_stories

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
use MediaWords::StoryVectors;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my ( $num_stories ) = $db->query( "select count(*) from scratch.revector_stories" )->flat;

    my $num_stories_vectored;
    while ( 1 )
    {
        $db->query( "create temporary table _revector_stories ( stories_id int )" );
        my $stories_ids = $db->query( <<END )->flat;
insert into _revector_stories select stories_id from scratch.revector_stories limit 100 returning *
END

        return unless ( @{ $stories_ids } );

        for my $stories_id ( @{ $stories_ids } )
        {
            my $story = $db->find_by_id( 'stories', $stories_id );
            MediaWords::StoryVectors::update_story_sentence_words_and_language( $db, $story );
        }

        $db->query( <<END );
delete from scratch.revector_stories where stories_id in ( select stories_id from _revector_stories )
END

        $db->query( "discard temp" );

        $num_stories_vectored += @{ $stories_ids };

        print STDERR "stories revectored: $num_stories_vectored / $num_stories\n";
    }
}

main();
