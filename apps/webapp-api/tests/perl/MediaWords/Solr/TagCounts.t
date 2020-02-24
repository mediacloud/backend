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
    $db->query('DELETE FROM tags WHERE tag LIKE ?', 'test_%');

    my $test_stories = $db->query( "select * from stories order by md5( stories_id::text )" )->hashes;

    my $num_tag_sets = 2;
    my $num_tags     = 5;
    for my $tsi ( 1 .. $num_tag_sets )
    {
        my $tag_set = $db->create( 'tag_sets', { name => "tag_set_$tsi", label => "Tag Set $tsi" } );
        for my $ti ( 1 .. $num_tags )
        {
            my $tag =
              $db->create( 'tags', { tag => "tag_$ti", label => "Tag $ti", tag_sets_id => $tag_set->{ tag_sets_id } } );
            my $num_tag_stories = $tag->{ tags_id } * 2;
            for my $i ( 1 .. $num_tag_stories )
            {
                my $tag_story = shift( @{ $test_stories } );
                push( @{ $test_stories }, $tag_story );
                $db->query( <<SQL, $tag->{ tags_id }, $tag_story->{ stories_id } );
insert into stories_tags_map ( tags_id, stories_id ) values ( ?, ? ) on conflict do nothing
SQL
            }
        }
    }

    MediaWords::Test::Solr::setup_test_index( $db );

    my $query_media_id = $media->{ medium_1 }->{ media_id };
    my $got_tag_counts = MediaWords::Solr::TagCounts::query_tag_counts( $db, { q => "media_id:$query_media_id" } );

    my $expected_tag_counts = $db->query( <<SQL, $query_media_id )->hashes;
with tag_counts as (
    select count(*) c, stm.tags_id
        from stories_tags_map stm
            join stories s using ( stories_id )
        where
            s.media_id = ?
        group by stm.tags_id
)

select c count, t.*, ts.name tag_set_name, ts.label tag_set_label
    from tags t
        join tag_sets ts using ( tag_sets_id )
        join tag_counts tc using ( tags_id )
    order by c desc limit 100
SQL

    my $num_tag_counts = scalar( @{ $got_tag_counts } );
    map { ok( $got_tag_counts->[ $_ ]->{ count } >= $got_tag_counts->[ $_ + 1 ]->{ count }, "Individual tag counts" ) }
      ( 0 .. ( $num_tag_counts - 2 ) );

    cmp_bag( $got_tag_counts, $expected_tag_counts, "Tag counts" );

    # Solr might not have committed tag counts just yet, so wait for the right count to appear
    my $single_tag_count;
    for ( my $x = 0; $x <= 20; ++$x ) {
        $single_tag_count = MediaWords::Solr::TagCounts::query_tag_counts(  #
            $db,                                                            #
            { q => "media_id:$query_media_id", limit => 1 },                #
        );                                                                  #
        if ( $single_tag_count->[ 0 ]->{ tags_id } == $expected_tag_counts->[ 0 ]->{ tags_id }) {
            last;
        }
        INFO "Retrying...";
        sleep( 1 );
    }

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
