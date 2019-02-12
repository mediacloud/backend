#!/usr/bin/env perl

use strict;
use warnings;

use MediaWords::CommonLibs;

use English '-no_match_vars';

use Data::Dumper;
use Encode;
use Test::More;
use Test::Deep;

use MediaWords::Solr::Query;
use MediaWords::Test::DB;
use MediaWords::Test::DB::Create;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;

# run the given set of params against _gsifsop and verify that the given list of stories_ids (or undef) is returned
sub test_stories_id_query
{
    my ( $db, $params, $expected_stories_ids, $label ) = @_;

    my $got_stories_ids = MediaWords::Solr::Query::_get_stories_ids_from_stories_only_params( $db, $params );

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

sub test_solr_stories_only_query($)
{
    my ( $db ) = @_;

    test_stories_id_query( $db, { q  => '' }, undef, 'empty q' );
    test_stories_id_query( $db, { fq => '' }, undef, 'empty fq' );
    test_stories_id_query( $db, { q => '', fq => '' }, undef, 'empty q and fq' );
    test_stories_id_query( $db, { q => '', fq => '' }, undef, 'empty q and fq' );

    test_stories_id_query( $db, { q => 'stories_id:1' }, [ 1 ], 'simple q match' );
    test_stories_id_query( $db, { q => 'media_id:1' }, undef, 'simple q miss' );
    test_stories_id_query( $db, { q => '*:*', fq => 'stories_id:1' }, [ 1 ], 'simple fq match' );
    test_stories_id_query( $db, { q => '*:*', fq => 'media_id:1' }, undef, 'simple fq miss' );

    test_stories_id_query( $db, { q => 'media_id:1',   fq => 'stories_id:1' }, undef, 'q hit / fq miss' );
    test_stories_id_query( $db, { q => 'stories_id:1', fq => 'media_id:1' },   undef, 'q miss / fq hit' );

    test_stories_id_query( $db, { q => '*:*', fq => [ 'stories_id:1', 'stories_id:1' ] }, [ 1 ], 'fq list hit' );
    test_stories_id_query( $db, { q => '*:*', fq => [ 'stories_id:1', 'media_id:1' ] }, undef, 'fq list miss' );

    test_stories_id_query( $db, { q => 'stories_id:1', fq => '' },             [ 1 ], 'q hit / empty fq' );
    test_stories_id_query( $db, { q => 'stories_id:1', fq => [] },             [ 1 ], 'q hit / empty fq list' );
    test_stories_id_query( $db, { q => '*:*',          fq => 'stories_id:1' }, [ 1 ], '*:* q / fq hit' );
    test_stories_id_query( $db, { fq => 'stories_id:1' }, undef, 'empty q, fq hit' );
    test_stories_id_query( $db, { q  => '*:*' },          undef, '*:* q' );

    test_stories_id_query( $db, { q => 'stories_id:( 1 2 3 )' }, [ 1, 2, 3 ], 'q list' );
    test_stories_id_query(
        $db,
        { q => 'stories_id:( 1 2 3 )', fq => 'stories_id:( 1 3 4 )' },
        [ 1, 3 ],
        'q list / fq list intersection'
    );
    test_stories_id_query( $db, { q => '( stories_id:2 )' }, [ 2 ], 'q parens' );
    test_stories_id_query( $db, { q => '(stories_id:3)' },   [ 3 ], 'q parens no spaces' );

    test_stories_id_query( $db, { q => 'stories_id:4 and stories_id:4' }, [ 4 ], 'q simple and' );
    test_stories_id_query( $db, { q => 'stories_id:( 1 2 3 ) and stories_id:( 2 3 4 )' }, [ 2, 3 ], 'q and intersection' );
    test_stories_id_query( $db, { q => 'stories_id:( 1 2 3 ) and stories_id:( 4 5 6 )' }, [], 'q and empty intersection' );

    test_stories_id_query(
        $db,
        { q => 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and stories_id:( 3 4 ) )' },
        [ 3, 4 ],
        'q complex and intersection'
    );
    test_stories_id_query( $db, { q => 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and media_id:1 )' },
        undef, 'q complex and intersection miss' );
    test_stories_id_query( $db, { q => 'stories_id:( 1 2 3 4 ) and ( stories_id:( 2 3 4 5 6 ) and stories_id:( 243 ) )' },
        [], 'q complex and intersection empty' );
    test_stories_id_query(
        $db,
        { q => 'stories_id:( 1 2 3 4 ) and stories_id:( 2 3 4 5 6 ) and stories_id:( 3 4 )' },
        [ 3, 4 ],
        'q complex and intersection'
    );

    test_stories_id_query( $db, { q => 'stories_id:1 and ( stories_id:2 and ( stories_id:3 and obama ) )' },
        undef, 'q complex boolean query with buried miss' );
    test_stories_id_query( $db, { q => '( ( stories_id:1 or stories_id:2 ) and stories_id:3 )' },
        undef, 'q complex boolean query with buried or' );

    test_stories_id_query( $db, { q => 'stories_id:( 1 2 3 4 5 6 )', foo => 'bar' }, undef, 'unrecognized parameters' );
    test_stories_id_query( $db, { q => 'stories_id:( 1 2 3 4 5 6 )', start => '2' }, [ 3, 4, 5, 6 ], 'start parameter' );
    test_stories_id_query(
        $db,
        { q => 'stories_id:( 1 2 3 4 5 6 )', start => '2', rows => 2 },
        [ 3, 4 ],
        'start and rows parameter'
    );
    test_stories_id_query( $db, { q => 'stories_id:( 1 2 3 4 5 6 )', rows => 2 }, [ 1, 2 ], 'rows parameter' );
}

# generate a utf8 string and append it to the title of the given stories, both in the hashes and in
# the database, and also add a sentence including the utf8 string to the db.  return the add utf8 string.
sub append_utf8_string_to_stories($$)
{
    my ( $db, $stories ) = @_;

    my $utf8_string = "ind\x{ed}gena";

    # my $utf8_string = "foobarbaz";

    for my $story ( @{ $stories } )
    {
        $story->{ title } = "$story->{ title } $utf8_string";
        $db->update_by_id( 'stories', $story->{ stories_id }, { title => $story->{ title } } );

        $db->query(
            <<SQL,
            INSERT INTO story_sentences (
                stories_id,
                sentence_number,
                sentence,
                media_id,
                publish_date,
                language,
                is_dup
            )
            SELECT
                stories_id,

                -- Table seems to be prefilled with some stories already
                100000 AS sentence_number,

                ?,
                media_id,
                publish_date,
                language,
                false
            FROM stories
            WHERE stories_id = ?
SQL
            encode_utf8( $utf8_string ), $story->{ stories_id }
        );
    }

    return $utf8_string;
}

# tests that require solr to be running
sub test_query($)
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
        my $got_num_stories = MediaWords::Solr::Query::get_num_found( $db, { q => '*:*' } );
        is( $got_num_stories, $expected_num_stories, 'get_num_found' );
    }

    {
        # search_for_processed_stories_ids
        my $first_story = $db->query( <<SQL )->hash;
select * from processed_stories order by processed_stories_id asc limit 1
SQL

        my $got_processed_stories_ids = MediaWords::Solr::Query::search_for_processed_stories_ids( $db, '*:*', undef, 0, 1 );
        is( scalar( @{ $got_processed_stories_ids } ), 1, "search_for_processed_stories_ids count" );
        is(
            $got_processed_stories_ids->[ 0 ],
            $first_story->{ processed_stories_id },
            "search_for_processed_stories_ids id"
        );
    }

    {
        # search_for_stories_ids
        my $story = pop( @{ $test_stories } );
        my $got_stories_ids =
          MediaWords::Solr::Query::search_for_stories_ids( $db, { q => "stories_id:$story->{ stories_id }" } );
        is_deeply( $got_stories_ids, [ $story->{ stories_id } ], "search_for_stories_ids" );
    }

    {
        # search_for_stories

        # search for stories_id range to prevent search_for_stories_id from using the stories_id_only_params shortcut
        my $expected_stories = $db->query( "select * from stories order by stories_id desc limit 10" )->hashes;
        my $min_stories_id   = $expected_stories->[ -1 ]->{ stories_id };
        my $got_stories      = MediaWords::Solr::Query::search_for_stories(
            $db,    #
            { q => '*:*', fq => "stories_id:[$min_stories_id TO *]" },    #
        );

        my $fields = [ qw/title publish_date url guid media_id language/ ];
        MediaWords::Test::DB::rows_match( 'search_for_stories', $got_stories, $expected_stories, 'stories_id', $fields );
    }

    {
        # query_matching_sentences
        my $story = pop( @{ $test_stories } );
        my $story_sentences = $db->query( <<SQL, $story->{ stories_id } )->hashes;
select * from story_sentences where stories_id = ?
SQL
        my ( $test_word ) = grep { length( $_ ) > 3 } split( ' ', $story_sentences->[ 0 ]->{ sentence } );

        $test_word = lc( $test_word );

        my $expected_sentences = [ grep { $_->{ sentence } =~ /$test_word/i } @{ $story_sentences } ];
        my $query              = "$test_word* and stories_id:$story->{ stories_id }";
        my $got_sentences      = MediaWords::Solr::Query::query_solr_for_matching_sentences( $db, { q => $query } );

        my $fields = [ qw/stories_id sentence_number sentence media_id publish_date language/ ];
        MediaWords::Test::DB::rows_match( "query_matching_sentences '$test_word'",
            $got_sentences, $expected_sentences, 'story_sentences_id', $fields );
    }

    {
        #query mmatching sentences with query with no text terms
        my $story = pop( @{ $test_stories } );
        my $story_sentences = $db->query( <<SQL, $story->{ stories_id } )->hashes;
select * from story_sentences where stories_id = ?
SQL
        my $query = "stories_id:$story->{ stories_id }";
        my $got_sentences = MediaWords::Solr::Query::query_solr_for_matching_sentences( $db, { q => $query } );

        my $fields = [ qw/stories_id sentence_number sentence media_id publish_date language/ ];
        MediaWords::Test::DB::rows_match( 'query_matching_sentences empty regex',
            $got_sentences, $story_sentences, 'story_sentences_id', $fields );
    }

    {
        eval { MediaWords::Solr::Query::query_solr( $db, { q => "publish_date:[foo TO bar]" } ) };
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

    my $got_q = MediaWords::Solr::Query::_insert_collection_media_ids( $db, "tags_id_media:$q_arg" );
    is( $got_q, $expected_q, "$label (tags_id_media)" );

    $got_q = MediaWords::Solr::Query::_insert_collection_media_ids( $db, "collections_id:$q_arg" );
    is( $got_q, $expected_q, "$label (collections_id)" );

    if ( $q_or_arg )
    {
        $got_q = MediaWords::Solr::Query::_insert_collection_media_ids( $db, "collections_id:$q_or_arg" );
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

sub test_query_tag_counts($)
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

    my $num_tag_sets = 2;
    my $num_tags     = 5;
    for my $tsi ( 1 .. $num_tag_sets )
    {
        my $tag_set = $db->create( 'tag_sets', { name => "tag_set_$tsi", label => "Tag Set $tsi" } );
        for my $ti ( 1 .. $num_tags )
        {
            my $tag =
              $db->create( 'tags', { tag => "tag_$ti", label => "Tag $ti", tag_sets_id => $tag_set->{ tag_sets_id } } );
            my $num_tag_stories = $tag->{ tags_id } * 5;
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
    my $got_tag_counts = MediaWords::Solr::Query::query_tag_counts( $db, { q => "media_id:$query_media_id" } );

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
    map { ok( $got_tag_counts->[ $_ ]->{ count } >= $got_tag_counts->[ $_ + 1 ]->{ count } ) }
      ( 0 .. ( $num_tag_counts - 2 ) );

    $got_tag_counts      = [ sort { $a->{ tags_id } <=> $b->{ tags_id } } @{ $got_tag_counts } ];
    $expected_tag_counts = [ sort { $a->{ tags_id } <=> $b->{ tags_id } } @{ $expected_tag_counts } ];

    is_deeply( $got_tag_counts, $expected_tag_counts );

    my $single_tag_count = MediaWords::Solr::Query::query_tag_counts(
        $db,    #
        { q => "media_id:$query_media_id", limit => 1 },    #
    );

    is( $single_tag_count->[ 0 ]->{ tags_id }, $expected_tag_counts->[ 0 ]->{ tags_id } );
    is( scalar( @{ $single_tag_count } ),      1 );

    my $query_tag_sets_id  = $got_tag_counts->[ -1 ]->{ tag_sets_id };
    my $tag_set_tag_counts = MediaWords::Solr::Query::query_tag_counts(
        $db,                                                #
        { q => "media_id:$query_media_id", tag_sets_id => $query_tag_sets_id },    #
    );

    $expected_tag_counts = [ grep { $_->{ tag_sets_id } == $query_tag_sets_id } @{ $expected_tag_counts } ];

    $tag_set_tag_counts = [ sort { $a->{ tags_id } <=> $b->{ tags_id } } @{ $tag_set_tag_counts } ];

    is_deeply( $tag_set_tag_counts, $expected_tag_counts );

}

sub main
{
    MediaWords::Test::DB::test_on_test_database( \&test_solr_stories_only_query );

    MediaWords::Test::DB::test_on_test_database( \&test_collections_id_queries );

    MediaWords::Test::Supervisor::test_with_supervisor( \&test_query, [ qw/solr_standalone/ ] );

    MediaWords::Test::Supervisor::test_with_supervisor( \&test_query_tag_counts, [ qw/solr_standalone/ ] );

    done_testing();
}

main();
