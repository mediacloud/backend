#!/usr/bin/env perl

# add ssw for every story in sopa_stories for which they are missing

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::StoryVectors;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $wordless_stories =
      $db->query( "select s.* " . "  from stories s, sopa_stories ss " . "  where s.stories_id = ss.stories_id and " .
          "    not exists ( select 1 from story_sentence_words ssw where ssw.stories_id = s.stories_id ) " )->hashes;

    for my $story ( @{ $wordless_stories } )
    {
        print STDERR "fix $story->{ title } [ $story->{ stories_id } ]\n";
        MediaWords::StoryVectors::update_story_sentence_words_and_language( $db, $story, 1, 1 );
    }
}

main();
