use strict;
use warnings;
use warnings;

use MediaWords::CommonLibs;

use English '-no_match_vars';

use Data::Dumper;
use Encode;
use Test::More;
use Test::Deep;

BEGIN
{
    use_ok( 'MediaWords::Solr' );
}

use MediaWords::DB;
use MediaWords::Solr::TagCounts;
use MediaWords::Test::API;
use MediaWords::Test::Solr;

# tests that require solr to be running
sub run_solr_tests($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::Solr::create_test_story_stack_for_indexing(
        $db,
        {
            medium_1 => { feed_1 => [ map { "story_$_" } ( 1 .. 15 ) ] },
            medium_2 => { feed_2 => [ map { "story_$_" } ( 16 .. 25 ) ] },
            medium_3 => { feed_3 => [ map { "story_$_" } ( 26 .. 50 ) ] },
        }
    );

    # Delete test tags added by create_test_story_stack_for_indexing()
    # (for whatever reason deleting from "tags" doesn't cascade into stories_tags_map)
    $db->query(<<SQL,
        WITH tag_ids_to_delete AS (
            SELECT tags_id
            FROM tags
            WHERE tag LIKE ?
        )
        DELETE FROM stories_tags_map
        WHERE tags_id IN (
            SELECT tags_id
            FROM tag_ids_to_delete
        )
SQL
        'test_%'
    );
    $db->query('DELETE FROM tags WHERE tag LIKE ?', 'test_%');

    my $test_stories = $db->query( <<SQL
        SELECT *
        FROM stories
        ORDER BY MD5(stories_id::TEXT)
SQL
    )->hashes;

    my $num_tag_sets = 2;
    my $num_tags     = 5;
    for my $tsi ( 1 .. $num_tag_sets )
    {
        my $tag_set = $db->create( 'tag_sets', { name => "tag_set_$tsi", label => "Tag Set $tsi" } );
        for my $ti ( 1 .. $num_tags )
        {
            my $tag = $db->create( 'tags', {
                tag => "tag_$ti",
                label => "Tag $ti",
                tag_sets_id => $tag_set->{ tag_sets_id }
            } );
            my $num_tag_stories = $tag->{ tags_id } * 2;
            for my $i ( 1 .. $num_tag_stories )
            {
                my $tag_story = shift( @{ $test_stories } );
                push( @{ $test_stories }, $tag_story );
                $db->query( <<SQL,
                    INSERT INTO stories_tags_map (stories_id, tags_id)
                    VALUES (?, ?)
                    ON CONFLICT DO NOTHING
SQL
                    $tag_story->{ stories_id }, $tag->{ tags_id }
                );
            }
        }
    }

    MediaWords::Test::Solr::setup_test_index( $db );

    my $query_media_id = $media->{ medium_1 }->{ media_id };
    my $got_tag_counts = MediaWords::Solr::TagCounts::query_tag_counts( $db, { q => "media_id:$query_media_id" } );

    my $expected_tag_counts = $db->query( <<SQL,
        WITH tag_counts AS (
            SELECT
                COUNT(*) AS c,
                stories_tags_map.tags_id
            FROM stories_tags_map
                INNER JOIN stories USING (stories_id)
            WHERE stories.media_id = ?
            GROUP BY stories_tags_map.tags_id
        )

        SELECT
            tag_counts.c AS count,
            tags.*,
            tag_sets.name AS tag_set_name,
            tag_sets.label AS tag_set_label
        FROM tags
            INNER JOIN tag_sets USING (tag_sets_id)
            INNER JOIN tag_counts USING (tags_id)
        ORDER BY
            tag_counts.c DESC,
            tags.tags_id ASC
        LIMIT 100
SQL
        $query_media_id
    )->hashes;

    my $num_tag_counts = scalar( @{ $got_tag_counts } );
    map { ok( $got_tag_counts->[ $_ ]->{ count } >= $got_tag_counts->[ $_ + 1 ]->{ count }, "Individual tag counts" ) }
      ( 0 .. ( $num_tag_counts - 2 ) );

    cmp_bag( $got_tag_counts, $expected_tag_counts, "Tag counts" );

    # Solr might not have committed tag counts just yet, so wait for the right count to appear
    my $single_tag_count = MediaWords::Solr::TagCounts::query_tag_counts(   #
        $db,                                                                #
        { q => "media_id:$query_media_id", limit => 1 },                    #
    );

    is( $single_tag_count->[ 0 ]->{ tags_id }, $expected_tag_counts->[ 0 ]->{ tags_id }, "Tag count's tag ID" );
    is( scalar( @{ $single_tag_count } ),      1, "Single tag count" );

    my $query_tag_sets_id  = $got_tag_counts->[ -1 ]->{ tag_sets_id };
    my $tag_set_tag_counts = MediaWords::Solr::TagCounts::query_tag_counts( $db,
        { q => "media_id:$query_media_id", tag_sets_id => $query_tag_sets_id } );

    $expected_tag_counts = [ grep { $_->{ tag_sets_id } == $query_tag_sets_id } @{ $expected_tag_counts } ];

    cmp_bag( $tag_set_tag_counts, $expected_tag_counts, "Tag set tag counts" );

}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    run_solr_tests( $db );

    done_testing();
}

main();
