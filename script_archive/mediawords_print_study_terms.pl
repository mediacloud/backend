#!/usr/bin/perl

# print out the stories and terms for grading for the term study

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;

my $_story_tag_sets = [ qw(manual_term Calais Yahoo NYTTopics) ];

# print the text and the tags of the given story
sub print_story
{
    my ( $db, $story ) = @_;

    my @tags = $db->resultset( 'Tags' )->search(
        {
            'tag_sets_id.name'             => $_story_tag_sets,
            'stories_tags_maps.stories_id' => $story->stories_id
        },
        { join => { 'stories_tags_maps' => { 'tags_id' => 'tag_sets_id' } } }
    );

    my $tag_sets_hash = {};
    my $tag_hash      = {};
    for my $tag ( @tags )
    {
        $tag_hash->{ lc( $tag->tag ) } = 1;
        $tag_sets_hash->{ $tag->tag_sets_id->name } = 1;
    }

    if ( !$tag_sets_hash->{ manual_term } )
    {
        next;
    }

    #    if (!@tags) {
    #        print "(no tags for story " . $story->stories_id . ")\n";
    #    } else {
    #        for my $ts (@{$_story_tag_sets}) {
    #            if (!$tag_sets_hash->{$ts}) {
    #                print "(no $ts tags for story " . $story->stories_id . ")\n";
    #            }
    #        }
    #    }

    print "\nSTORY ID: " . $story->stories_id . "\n\n";

    print "\nTITLE: " . $story->title . "\n\n";

    print "\nTEXT:\n\n";

    print $story->story_texts_id->story_text;

    print "\nTAGS:\n\n";

    for my $t ( sort { $a cmp $b } keys( %{ $tag_hash } ) )
    {
        print "$t\n";
    }

    print( ( "*" x 40 ) . "\n" );
}

# given the source tag, print all stories and tags from that source tag
sub print_tag_stories
{
    my ( $db, $feed_tag ) = @_;

    print( ( "*" x 40 ) . "\n" . "START FEED: " . $feed_tag->tag . "\n" . ( "*" x 40 ) . "\n" );

    my @stories =
      $db->resultset( 'Stories' )
      ->search( { 'stories_tags_maps.tags_id' => $feed_tag->tags_id }, { join => 'stories_tags_maps' } );

    for my $story ( @stories )
    {
        print_story( $db, $story );
    }

}

sub main
{

    my $db = MediaWords::DB->authenticate();

    my @feed_tags = $db->resultset( 'Tags' )->search( { 'tag_sets_id.name' => 'term_study' }, { join => 'tag_sets_id' } );
    for my $feed_tag ( @feed_tags )
    {
        print_tag_stories( $db, $feed_tag );
    }
}

main();
