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

    print "STORY: " . $story->title . "\n";

    my $text = $story->story_texts_id->story_text;

    my $terms = MediaWords::Tagger::get_all_tags($text);

    while ( my ( $tag_set_name, $tag_names ) = each( %{$terms} ) )
    {

        print "TAGS $tag_set_name: " . join( ', ', @{$tag_names} ) . "\n";

        my $tag_set = $db->resultset('TagSets')->find_or_create( { name => $tag_set_name } );

        my @stms = $db->resultset('StoriesTagsMap')->search(
            {
                'tags_id.tag_sets_id' => $tag_set->tag_sets_id,
                'me.stories_id'       => $story->stories_id
            },
            { join => 'tags_id' }
        );
        map { $_->delete } @stms;

        for my $tag_name ( @{$tag_names} )
        {
            my $tag = $db->resultset('Tags')->find_or_create(
                {
                    tag         => $tag_name,
                    tag_sets_id => $tag_set->tag_sets_id
                }
            );

            $db->resultset('StoriesTagsMap')->create(
                {
                    tags_id    => $tag->tags_id,
                    stories_id => $story->stories_id
                }
            );
        }
    }

    print "\n";
}

# add term_study tags to all the stories with the given tag
sub add_tags_to_feed_stories
{
    my ( $db, $feed_tag ) = @_;

    my @stories =
      $db->resultset('Stories')
      ->search( { 'stories_tags_maps.tags_id' => $feed_tag->tags_id }, { join => 'stories_tags_maps' } );

    for my $story (@stories)
    {
        add_tags_to_story( $db, $story );
    }

}

sub main
{

    my $db = MediaWords::DB::authenticate();

    my @feed_tags = $db->resultset('Tags')->search( { 'tag_sets_id.name' => 'term_study' }, { join => 'tag_sets_id' } );
    for my $feed_tag (@feed_tags)
    {
        add_tags_to_feed_stories( $db, $feed_tag );
    }
}

main();
