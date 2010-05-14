#!/usr/bin/perl

# text extraction taking feed id, date, tag name

# usage: mediawords_add_nyt_tags.pl [<process num> <num of processes>]
#
# to run several instances in parallel, supply the number of the given process and the total number of processes
# example:
# mediawords_add_nyt_tags.pl 1 4 &
# mediawords_add_nyt_tags.pl 2 4 &
# mediawords_add_nyt_tags.pl 3 4 &
# mediawords_add_nyt_tags.pl 4 4 &

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Tagger;
use MediaWords::Tagger::NYTTopics;

my $_nyt_tag_sets_id;
my $_tags_id_cache = {};

# get cached id of the nyttopics tag
sub get_tags_id
{
    my ( $db, $term ) = @_;

    if ( $_tags_id_cache->{ $term } )
    {
        return $_tags_id_cache->{ $term };
    }

    my $tag = $db->resultset( 'Tags' )->find_or_create(
        {
            tag         => $term,
            tag_sets_id => $_nyt_tag_sets_id
        }
    );

    $_tags_id_cache->{ $term } = $tag->tags_id;

    return $tag->tags_id;
}

# run the story text through each terming engine
sub add_tags_to_story
{
    my ( $db, $story ) = @_;

    my $text = $story->get_text();

    my $terms = MediaWords::Tagger::NYTTopics::get_tags( join( "\n", $story->title, $story->description, $text ) );

    $_nyt_tag_sets_id ||= $db->resultset( 'TagSets' )->find_or_create( { name => 'NYTTopics' } )->tag_sets_id;

    my @stms = $db->resultset( 'StoriesTagsMap' )->search(
        {
            'tags_id.tag_sets_id' => $_nyt_tag_sets_id,
            'me.stories_id'       => $story->stories_id
        },
        { join => 'tags_id' }
    );
    map { $_->delete } @stms;

    print "STORY: " . $story->stories_id . " " . $story->title . ": " . join( ', ', @{ $terms } ) . "\n";

    for my $tag_name ( @{ $terms } )
    {
        $db->resultset( 'StoriesTagsMap' )->create(
            {
                tags_id    => get_tags_id( $db, $tag_name ),
                stories_id => $story->stories_id
            }
        );
    }

}

sub main
{

    my ( $process_number, $number_processes ) = @ARGV;

    $process_number   ||= 1;
    $number_processes ||= 1;

    my $db = MediaWords::DB::authenticate();

    my $tagged_tag_set = $db->resultset( 'TagSets' )->find_or_create( { name => 'tagged' } );
    my $tagged_tag =
      $db->resultset( 'Tags' )->find_or_create( { tag => 'NYTTopics', tag_sets_id => $tagged_tag_set->tag_sets_id } );
    my $nyt_tagset = $db->resultset( 'TagSets' )->find_or_create( { name => 'NYTTopics' } );

    my $last_stories_id = 0;
    while ( 1 )
    {
        print "last_stories_id: $last_stories_id\n";

        my @stories = $db->resultset( 'Stories' )->search(
            { 'stories_id' => { '>' => $last_stories_id } },
            {
                rows     => 1000,
                order_by => 'stories_id asc'
            }
        );
        if ( !@stories )
        {
            last;
        }

        for my $story ( @stories )
        {
            if ( ( ( $story->stories_id + $process_number ) % $number_processes ) == 0 )
            {
                my @tagged = $story->search_related(
                    'stories_tags_maps',
                    { 'tags_id.tag_sets_id' => $nyt_tagset->tag_sets_id },
                    { 'join'                => 'tags_id' }
                );
                if ( !@tagged )
                {
                    add_tags_to_story( $db, $story );
                    $db->resultset( 'StoriesTagsMap' )->find_or_create(
                        {
                            stories_id => $story->stories_id,
                            tags_id    => $tagged_tag->tags_id
                        }
                    );
                }
            }

            $last_stories_id = $story->stories_id;
        }
    }
}

main();
