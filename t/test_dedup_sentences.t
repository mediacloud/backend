use strict;
use warnings;

# test that inserts and updates on stories in controversy_stories are correctly mirrored to cd.live_stories

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use English '-no_match_vars';

use Data::Dumper;
use Test::More tests => 4;
use Test::Deep;

use MediaWords::StoryVectors;
use MediaWords::Test::DB;
use MediaWords::Util::SQL;

BEGIN
{
    use_ok( 'MediaWords::DB' );
}

sub _insert_story_sentences
{
    my ( $db, $story, $sentences ) = @_;

    my $sentence_refs = [];
    for ( my $sentence_num = 0 ; $sentence_num < @{ $sentences } ; $sentence_num++ )
    {
        my $sentence = $sentences->[ $sentence_num ];

        my $sentence_ref = {};
        $sentence_ref->{ sentence }         = $sentence;
        $sentence_ref->{ language }         = 'en';
        $sentence_ref->{ sentence_number }  = $sentence_num;
        $sentence_ref->{ stories_id }       = $story->{ stories_id };
        $sentence_ref->{ media_id }         = $story->{ media_id };
        $sentence_ref->{ publish_date }     = $story->{ publish_date };
        $sentence_ref->{ disable_triggers } = MediaWords::DB::story_triggers_disabled();

        push( @{ $sentence_refs }, $sentence_ref );
    }

    MediaWords::StoryVectors::_insert_story_sentences( $db, $story, $sentence_refs );
}

sub test_dedup_sentences
{
    my ( $db ) = @_;

    my $medium = {
        name      => "test dedup sentences",
        url       => "url://test/dedup/sentences",
        moderated => 't',
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

    $story_a->{ sentences } = [ 'foo', 'bar', 'baz' ];

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

    $story_b->{ sentences } = [ 'bar foo', 'bar', 'foo', 'foo bar', 'foo bar' ];

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

    $story_c->{ sentences } = [ 'foo', 'bar', 'foo bar' ];

    $story_a->{ ds } = MediaWords::StoryVectors::dedup_sentences( $db, $story_a, $story_a->{ sentences } );
    _insert_story_sentences( $db, $story_a, $story_a->{ ds } );

    $story_b->{ ds } = MediaWords::StoryVectors::dedup_sentences( $db, $story_b, $story_b->{ sentences } );
    _insert_story_sentences( $db, $story_b, $story_b->{ ds } );

    $story_c->{ ds } = MediaWords::StoryVectors::dedup_sentences( $db, $story_c, $story_c->{ sentences } );
    _insert_story_sentences( $db, $story_c, $story_c->{ ds } );

    cmp_deeply( $story_a->{ ds }, $story_a->{ sentences }, 'story a' );
    cmp_deeply( $story_b->{ ds }, [ 'bar foo', 'foo bar' ], 'story b' );
    cmp_deeply( $story_c->{ ds }, $story_c->{ sentences }, 'story c' );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            use Encode;
            my ( $db ) = @_;

            test_dedup_sentences( $db );
        }
    );
}

main();
