#!/usr/bin/perl

# import nyttopics tags from duplicate machine

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;

my $_tags = {};

# get the id corresponding to the tag name.  cache the result for each tag name.
sub get_tags_id
{
    my ( $db, $nyt_tagset, $tag_name ) = @_;

    if ( my $tags_id = $_tags->{$tag_name} )
    {
        return $tags_id;
    }

    my $tag = $db->resultset('Tags')->find_or_create(
        {
            tag         => $tag_name,
            tag_sets_id => $nyt_tagset->tag_sets_id
        }
    );

    $_tags->{$tag_name} = $tag->tags_id;

    return $tag->tags_id;
}

sub main
{

    my $db = MediaWords::DB::authenticate();

    my $nyt_tagset = $db->resultset('TagSets')->find_or_create( { name => 'NYTTopics' } );

    my @existing_tags =
      $db->resultset('StoriesTagsMap')
      ->search( { 'tags_id.tag_sets_id' => $nyt_tagset->tag_sets_id }, { 'join' => 'tags_id' } );
    if (@existing_tags)
    {
        die("NYTTopics story tag mappings already exist.");
    }

    while ( my $line = <> )
    {
        chomp($line);

        if ( !( $line =~ /^\s*([0-9]+) (.*)/ ) )
        {
            die("Unable to parse line: $line");
        }

        my ( $stories_id, $tag_name ) = ( $1, $2 );

        my $tags_id = get_tags_id( $db, $nyt_tagset, $tag_name );
        if ( !$tags_id )
        {
            die("Unable to find tag $tag_name");
        }

        $db->resultset('StoriesTagsMap')->create(
            {
                stories_id => $stories_id,
                tags_id    => $tags_id
            }
        );

        print "$stories_id $tags_id\n";
    }
}

main();
