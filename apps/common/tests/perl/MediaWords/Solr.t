use strict;
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
use MediaWords::Test::DB::Create;
use MediaWords::Test::Solr;
use MediaWords::Test::Rows;

# run the given set of params against _gsifsop and verify that the given list of stories_ids (or undef) is returned
sub test_stories_id_query
{
    my ( $params, $expected_stories_ids, $label ) = @_;

    my $got_stories_ids = MediaWords::Solr::_get_stories_ids_from_stories_only_params( $params );

    if ( $expected_stories_ids )
    {
        ok( $got_stories_ids, "$label stories_ids defined" );
        return unless ( $got_stories_ids );

        is( scalar( @{ $got_stories_ids } ), scalar( @{ $expected_stories_ids } ), "$label expected story count" );

        my $got_story_lookup = {};
        map { $got_story_lookup->{ $_ } = 1 } @{ $got_stories_ids };

        map { ok( $got_story_lookup->{ $_ }, "$label: expected stories_id $_" ) } @{ $expected_stories_ids };
    }
    else
    {
        is( $got_stories_ids, undef, "$label: expected undef" );
    }
}

sub test_solr_stories_only_query()
{
    test_stories_id_query( { q  => '' }, undef, 'empty q' );
    test_stories_id_query( { fq => '' }, undef, 'empty fq' );
    test_stories_id_query( { q => '', fq => '' }, undef, 'empty q and fq' );
    test_stories_id_query( { q => '', fq => '' }, undef, 'empty q and fq' );

    test_stories_id_query( { q => 'stories_id:1' }, [ 1 ], 'simple q match' );
    test_stories_id_query( { q => 'media_id:1' }, undef, 'simple q miss' );
    test_stories_id_query( { q => '*:*', fq => 'stories_id:1' }, [ 1 ], 'simple fq match' );
    test_stories_id_query( { q => '*:*', fq => 'media_id:1' }, undef, 'simple fq miss' );

    test_stories_id_query( { q => 'media_id:1',   fq => 'stories_id:1' }, undef, 'q hit / fq miss' );
    test_stories_id_query( { q => 'stories_id:1', fq => 'media_id:1' },   undef, 'q miss / fq hit' );

    test_stories_id_query( { q => '*:*', fq => [ 'stories_id:1', 'stories_id:1' ] }, [ 1 ], 'fq list hit' );
    test_stories_id_query( { q => '*:*', fq => [ 'stories_id:1', 'media_id:1' ] }, undef, 'fq list miss' );

    test_stories_id_query( { q => 'stories_id:1', fq => '' },             [ 1 ], 'q hit / empty fq' );
    test_stories_id_query( { q => 'stories_id:1', fq => [] },             [ 1 ], 'q hit / empty fq list' );
    test_stories_id_query( { q => '*:*',          fq => 'stories_id:1' }, [ 1 ], '*:* q / fq hit' );
    test_stories_id_query( { fq => 'stories_id:1' }, undef, 'empty q, fq hit' );
    test_stories_id_query( { q  => '*:*' },          undef, '*:* q' );

    test_stories_id_query( { q => 'stories_id:( 1 2 3 )' }, [ 1, 2, 3 ], 'q list' );
    test_stories_id_query(
        { q => 'stories_id:( 1 2 3 )', fq => 'stories_id:( 1 3 4 )' },
        [ 1, 3 ],
        'q list / fq list intersection'
    );
    test_stories_id_query( { q => '( stories_id:2 )' }, [ 2 ], 'q parens' );
    test_stories_id_query( { q => '(stories_id:3)' },   [ 3 ], 'q parens no spaces' );

    test_stories_id_query( { q => 'stories_id:4 and stories_id:4' }, [ 4 ], 'q simple and' );
    test_stories_id_query( { q => 'stories_id:( 1 2 3 ) and stories_id:( 2 3 4 )' }, [ 2, 3 ], 'q and intersection' );
    test_stories_id_query( { q => 'stories_id:( 1 2 3 ) and stories_id:( 4 5 6 )' }, [], 'q and empty intersection' );

    test_stories_id_query(
        { q => 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and stories_id:( 3 4 ) )' },
        [ 3, 4 ],
        'q complex and intersection'
    );
    test_stories_id_query( { q => 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and media_id:1 )' },
        undef, 'q complex and intersection miss' );
    test_stories_id_query( { q => 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and stories_id:( 243 ) )' },
        [], 'q complex and intersection empty' );
    test_stories_id_query(
        { q => 'stories_id:( 1 2 3 4 ) and stories_id:( 2 3 4 5 6 ) and stories_id:( 3 4 )' },
        [ 3, 4 ],
        'q complex and intersection'
    );

    test_stories_id_query( { q => 'stories_id:1 and ( stories_id:2 and ( stories_id:3 and obama ) )' },
        undef, 'q complex boolean query with buried miss' );
    test_stories_id_query( { q => '( ( stories_id:1 or stories_id:2 ) and stories_id:3 )' },
        undef, 'q complex boolean query with buried or' );

    test_stories_id_query( { q => 'stories_id:( 1 2 3 4 5 6 )', foo => 'bar' }, undef, 'unrecognized parameters' );
    test_stories_id_query( { q => 'stories_id:( 1 2 3 4 5 6 )', start => '2' }, [ 3, 4, 5, 6 ], 'start parameter' );
    test_stories_id_query(
        { q => 'stories_id:( 1 2 3 4 5 6 )', start => '2', rows => 2 },
        [ 3, 4 ],
        'start and rows parameter'
    );
    test_stories_id_query( { q => 'stories_id:( 1 2 3 4 5 6 )', rows => 2 }, [ 1, 2 ], 'rows parameter' );
}

# tests that require solr to be running
sub run_solr_tests($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::Solr::create_indexed_test_story_stack(
        $db,
        {
            medium_1 => { feed_1 => [ map { "story_$_" } ( 1 .. 15 ) ] },
            medium_2 => { feed_2 => [ map { "story_$_" } ( 16 .. 25 ) ] },
            medium_3 => { feed_3 => [ map { "story_$_" } ( 26 .. 50 ) ] },
        }
    );

    my $test_stories = $db->query( "select * from stories order by md5( stories_id::text )" )->hashes;

    {
        # basic query
        my $story = pop( @{ $test_stories } );
        MediaWords::Test::Solr::test_story_query( $db, '*:*', $story, 'simple story' );
    }

    {
        # get_num_found
        my ( $expected_num_stories ) = $db->query( "select count(*) from stories" )->flat;
        my $got_num_stories = MediaWords::Solr::get_num_found( $db, { q => '*:*' } );
        is( $got_num_stories, $expected_num_stories, 'get_num_found' );
    }

    {
        # search_solr_for_processed_stories_ids
        my $first_story = $db->query( <<SQL )->hash;
select * from processed_stories order by processed_stories_id asc limit 1
SQL

        my $got_processed_stories_ids = MediaWords::Solr::search_solr_for_processed_stories_ids( $db, '*:*', undef, 0, 1 );
        is( scalar( @{ $got_processed_stories_ids } ), 1, "search_solr_for_processed_stories_ids count" );
        is(
            $got_processed_stories_ids->[ 0 ],
            $first_story->{ processed_stories_id },
            "search_solr_for_processed_stories_ids id"
        );
    }

    {
        # search_solr_for_stories_ids
        my $story = pop( @{ $test_stories } );
        my $got_stories_ids = MediaWords::Solr::search_solr_for_stories_ids( $db, { q => "stories_id:$story->{ stories_id }" } );
        is_deeply( $got_stories_ids, [ $story->{ stories_id } ], "search_solr_for_stories_ids" );
    }

    {
        eval { MediaWords::Solr::query_solr( $db, { q => "publish_date:[foo TO bar]" } ) };
        ok( $@ =~ /range queries are not allowed/, "range queries not allowed: '$@'" );
    }
}

sub test_collections_id_result($$$)
{
    my ( $db, $tags, $label ) = @_;

    my $tags_ids = [ map { $_->{ tags_id } } @{ $tags } ];

    my ( $q_arg, $q_or_arg );
    if ( scalar( @{ $tags_ids } ) > 1 )
    {
        $q_arg    = "(" . join( ' ',    @{ $tags_ids } ) . ")";
        $q_or_arg = "(" . join( ' or ', @{ $tags_ids } ) . ")";
    }
    else
    {
        $q_arg = $tags_ids->[ 0 ];
    }

    my $expected_media_ids = [];
    for my $tag ( @{ $tags } )
    {
        for my $medium ( @{ $tag->{ media } } )
        {
            push( @{ $expected_media_ids }, $medium->{ media_id } );
        }
    }

    my $expected_q = 'media_id:(' . join( ' ', @{ $expected_media_ids } ) . ')';

    my $got_q = MediaWords::Solr::_insert_collection_media_ids( $db, "tags_id_media:$q_arg" );
    is( $got_q, $expected_q, "$label (tags_id_media)" );

    $got_q = MediaWords::Solr::_insert_collection_media_ids( $db, "collections_id:$q_arg" );
    is( $got_q, $expected_q, "$label (collections_id)" );

    if ( $q_or_arg )
    {
        $got_q = MediaWords::Solr::_insert_collection_media_ids( $db, "collections_id:$q_or_arg" );
        is( $got_q, $expected_q, "$label (collections_id with ors)" );
    }

}

sub test_collections_id_queries($)
{
    my ( $db ) = @_;

    my $num_tags          = 10;
    my $num_media_per_tag = 10;

    my $tag_set = $db->create( 'tag_sets', { name => 'test' } );

    my $tags;

    for my $tag_i ( 1 .. $num_tags )
    {
        my $tag = $db->create( 'tags', { tag_sets_id => $tag_set->{ tag_sets_id }, tag => "test_$tag_i" } );

        $tag->{ media } = [];
        for my $medium_i ( 1 .. $num_media_per_tag )
        {
            my $medium = MediaWords::Test::DB::Create::create_test_medium( $db, "tag $tag_i medium $medium_i" );
            $db->query( <<SQL, $tag->{ tags_id }, $medium->{ media_id } );
insert into media_tags_map ( tags_id, media_id ) values ( ?, ? )
SQL
            push( @{ $tag->{ media } }, $medium );
        }

        push( @{ $tags }, $tag );
    }

    test_collections_id_result( $db, [ $tags->[ 0 ] ], "single tags_id" );
    test_collections_id_result( $db, $tags, "all tags" );
    test_collections_id_result( $db, [ $tags->[ 0 ], $tags->[ 1 ], $tags->[ 2 ] ], "three tags" );

}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_solr_stories_only_query();

    test_collections_id_queries( $db );

    run_solr_tests( $db );

    done_testing();
}

main();
