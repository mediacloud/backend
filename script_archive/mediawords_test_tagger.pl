#!/usr/bin/perl

# text extraction taking feed id, date, tag name

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Tagger;

use constant DEFAULT_TAG_SET_NAME => 'term_study';

# run the story text through each terming engine
sub add_tags_to_story
{
    my ( $db, $story ) = @_;

    print "STORY: " . $story->title . ":" . $story->stories_id . "\n";

    my $text = $story->story_texts_id->story_text;

    my $terms = MediaWords::Tagger::get_tags_for_modules( $text, [ "Calais" ] );

}

# add term_study tags to all the stories with the given tag
sub add_tags_to_feed_stories
{
    my ( $db, $feed_tag ) = @_;

    my @stories =
      $db->resultset( 'Stories' )
      ->search( { 'stories_tags_maps.tags_id' => $feed_tag->tags_id }, { join => 'stories_tags_maps' } );

    for my $story ( @stories[ 10 .. 30 ] )
    {

        #      if ($story->stories_id == '289710') {
        add_tags_to_story( $db, $story );

        #      }
    }

}

sub main
{

    my $db = MediaWords::DB::authenticate();

    my @feed_tags = $db->resultset( 'Tags' )->search( { 'tag_sets_id.name' => 'term_study' }, { join => 'tag_sets_id' } );
    for my $feed_tag ( @feed_tags )
    {
        add_tags_to_feed_stories( $db, $feed_tag );
    }
}

main();
