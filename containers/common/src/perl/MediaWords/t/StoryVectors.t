use strict;
use warnings;

use English '-no_match_vars';

use Data::Dumper;
use Encode;
use Test::More tests => 7;
use Test::Deep;

use MediaWords::StoryVectors;
use MediaWords::Test::DB::Create;
use MediaWords::Util::SQL;

BEGIN
{
    use_ok( 'MediaWords::DB' );
}

sub test_dedup_sentences
{
    my ( $db ) = @_;

    my $medium = {
        name => "test dedup sentences",
        url  => "url://test/dedup/sentences",
    };
    $medium = $db->create( 'media', $medium );

    my $story_a = {
        media_id      => $medium->{ media_id },
        url           => 'url://story/a',
        guid          => 'guid://story/a',
        title         => 'story a',
        description   => 'description a',
        publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() ),
        collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() ),
        full_text_rss => 't'
    };
    $story_a = $db->create( 'stories', $story_a );

    $story_a->{ sentences } = [ 'foo baz', 'bar baz', 'baz baz' ];

    my $story_b = {
        media_id      => $medium->{ media_id },
        url           => 'url://story/b',
        guid          => 'guid://story/b',
        title         => 'story b',
        description   => 'description b',
        publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() ),
        collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() ),
        full_text_rss => 'f'
    };
    $story_b = $db->create( 'stories', $story_b );

    $story_b->{ sentences } = [ 'bar foo baz', 'bar baz', 'foo baz', 'foo bar baz', 'foo bar baz' ];

    my $story_c = {
        media_id      => $medium->{ media_id },
        url           => 'url://story/c',
        guid          => 'guid://story/c',
        title         => 'story c',
        description   => 'description c',
        publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - ( 90 * 86400 ) ),
        collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() ),
        full_text_rss => 'f'
    };
    $story_c = $db->create( 'stories', $story_c );

    $story_c->{ sentences } = [ 'foo baz', 'bar baz', 'foo bar baz' ];

    $story_a->{ ds } = MediaWords::StoryVectors::_insert_story_sentences( $db, $story_a, $story_a->{ sentences } );
    $story_b->{ ds } = MediaWords::StoryVectors::_insert_story_sentences( $db, $story_b, $story_b->{ sentences } );
    $story_c->{ ds } = MediaWords::StoryVectors::_insert_story_sentences( $db, $story_c, $story_c->{ sentences } );

    cmp_deeply( $story_a->{ ds }, $story_a->{ sentences }, 'story a' );
    cmp_deeply( $story_b->{ ds }, [ 'bar foo baz', 'foo bar baz' ], 'story b' );
    cmp_deeply( $story_c->{ ds }, $story_c->{ sentences }, 'story c' );

    my ( $expected_stat_sentences ) = $db->query(
        "select count(*) from story_sentences where media_id = ? and publish_date::date = ?::date",
        $medium->{ media_id },
        $story_a->{ publish_date }
    )->flat();

    my ( $got_stat_sentences ) = $db->query(
        "select num_sentences from media_stats where media_id = ? and stat_date = ?::date",
        $medium->{ media_id },
        $story_a->{ publish_date }
    )->flat();

    is( $got_stat_sentences, $expected_stat_sentences, "insert story sentences: media_stats" );
}

sub test_delete_story_sentences($)
{
    my ( $db ) = @_;

    my $label  = 'delete_story_sentences';
    my $medium = MediaWords::Test::DB::Create::create_test_medium( $db, $label );
    my $feed   = MediaWords::Test::DB::Create::create_test_feed( $db, $label, $medium );

    my $stories = [ map { MediaWords::Test::DB::Create::create_test_story( $db, "$label $_", $feed ) } ( 1 .. 10 ) ];

    # make sure nothing breaks when there are not sentences for a story
    MediaWords::StoryVectors::_delete_story_sentences( $db, $stories->[ 0 ] );

    my $test_story    = pop( @{ $stories } );
    my $num_sentences = 12;
    $db->query( <<SQL, $num_sentences, $test_story->{ stories_id } );
insert into story_sentences (sentence, sentence_number, stories_id, media_id, publish_date )
    select 'sentence ' || n::text, n, stories_id, media_id, publish_date
        from stories s
            cross join ( select generate_series(1, ?) as n ) a
        where s.stories_id = ?
SQL

    my $start_num_sentences = 100;
    $db->query(
        "update media_stats set num_sentences = ? where media_id = ? and stat_date = ?::date",
        $start_num_sentences,
        $test_story->{ media_id },
        $test_story->{ publish_date }
    );

    MediaWords::StoryVectors::_delete_story_sentences( $db, $test_story );

    my ( $got_num_sentences ) =
      $db->query( "select count(*) from story_sentences where stories_id = ?", $test_story->{ stories_id } )->flat();

    is( $got_num_sentences, 0, "$label story_sentences count" );

    my ( $got_stats_sentences ) = $db->query(
        "select num_sentences from media_stats where media_id = ? and stat_date = ?::date",
        $test_story->{ media_id },
        $test_story->{ publish_date }
    )->flat();

    is( $got_stats_sentences, $start_num_sentences - $num_sentences, "$label media_stats" );
}

sub main()
{
    my $db = MediaWords::DB::connect_to_db();

    test_dedup_sentences( $db );
    test_delete_story_sentences( $db );
}

main();
