use strict;
use warnings;

# test that inserts and updates on stories in topic_stories are correctly mirrored to snap.live_stories

use English '-no_match_vars';

use Test::More tests => 14;
use Test::Deep;

use MediaWords::DB;
use MediaWords::Util::SQL;

BEGIN
{
    use_ok( 'MediaWords::DB' );
}

sub add_topic_story
{
    my ( $db, $topic, $story ) = @_;

    $db->create( 'topic_stories', { stories_id => $story->{ stories_id }, topics_id => $topic->{ topics_id } } );
}

sub test_live_story_matches
{
    my ( $db, $topic, $story, $test_label ) = @_;

    my $live_story = $db->query( <<END, $topic->{ topics_id }, $story->{ stories_id } )->hash;
select * from snap.live_stories where topics_id = ? and stories_id = ?
END

    delete( $live_story->{ snap_live_stories_id } );
    delete( $live_story->{ topics_id } );
    delete( $live_story->{ topic_stories_id } );

    $live_story->{ publish_date } =~ s/T/ /g;
    $live_story->{ collect_date } =~ s/T/ /g;
    $story->{ publish_date } =~ s/T/ /g;
    $story->{ collect_date } =~ s/T/ /g;

    cmp_deeply( $live_story, $story, "$test_label: $story->{ title } should be in $topic->{ name } and match story" );
}

sub test_live_story_absent
{
    my ( $db, $topic, $story, $test_label ) = @_;

    my $live_story = $db->query( <<END, $topic->{ topics_id }, $story->{ stories_id } )->hash;
select * from snap.live_stories where topics_id = ? and stories_id = ?
END
    is( $live_story, undef, "$test_label: \$story->{ title } should be absent from \$topic->{ title }" );
}

sub update_story
{
    my ( $db, $story ) = @_;

    $story->{ url }         ||= '/' . rand();
    $story->{ guid }        ||= '/' . rand();
    $story->{ title }       ||= ' ' . rand();
    $story->{ description } ||= ' ' . rand();
    $story->{ publish_date } = MediaWords::Util::SQL::get_sql_date_from_epoch( time() - int( rand( 100000 ) ) );
    $story->{ collect_date } = MediaWords::Util::SQL::get_sql_date_from_epoch( time() - int( rand( 100000 ) ) );

    $db->update_by_id( 'stories', $story->{ stories_id }, $story );

    return $db->find_by_id( 'stories', $story->{ stories_id } );
}

sub test_live_stories
{
    my ( $db ) = @_;

    my $medium = {
        name => "test live stories",
        url  => "url://test/live/stories",
    };
    $medium = $db->create( 'media', $medium );

    my $topic_a = {
        name                => 'topic a',
        pattern             => '',
        solr_seed_query     => '',
        solr_seed_query_run => 'f',
        description         => 'topic A',
        start_date          => '2017-01-01',
        end_date            => '2017-02-01',
        job_queue           => 'mc',
        max_stories         => 100_000,
        platform            => 'web'
    };
    $topic_a = $db->create( 'topics', $topic_a );

    my $topic_b = {
        name                => 'topic b',
        pattern             => '',
        solr_seed_query     => '',
        solr_seed_query_run => 'f',
        description         => 'topic B',
        start_date          => '2017-01-01',
        end_date            => '2017-02-01',
        job_queue           => 'mc',
        max_stories         => 100_000,
        platform            => 'web'
    };
    $topic_b = $db->create( 'topics', $topic_b );

    my $story_a = {
        media_id      => $medium->{ media_id },
        url           => 'url://story/a',
        guid          => 'guid://story/a',
        title         => 'story a',
        description   => 'description a',
        publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 100000 ),
        collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 200000 ),
        full_text_rss => 't'
    };
    $story_a = $db->create( 'stories', $story_a );

    my $story_b = {
        media_id      => $medium->{ media_id },
        url           => 'url://story/b',
        guid          => 'guid://story/b',
        title         => 'story b',
        description   => 'description b',
        publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 300000 ),
        collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 400000 ),
        full_text_rss => 'f'
    };
    $story_b = $db->create( 'stories', $story_b );

    my $story_c = {
        media_id      => $medium->{ media_id },
        url           => 'url://story/c',
        guid          => 'guid://story/c',
        title         => 'story c',
        description   => 'description c',
        publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 500000 ),
        collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 600000 ),
        full_text_rss => 'f'
    };
    $story_c = $db->create( 'stories', $story_c );

    my $live_story = $db->query( "select * from snap.live_stories" )->hash;
    is( $live_story, undef, "live stories empty before cs insert" );

    add_topic_story( $db, $topic_a, $story_a );
    add_topic_story( $db, $topic_b, $story_b );
    add_topic_story( $db, $topic_a, $story_c );
    add_topic_story( $db, $topic_b, $story_c );

    test_live_story_matches( $db, $topic_a, $story_a, "after insert" );
    test_live_story_absent( $db, $topic_b, $story_a, "after insert" );

    test_live_story_matches( $db, $topic_b, $story_b, "after insert" );
    test_live_story_absent( $db, $topic_a, $story_b, "after insert" );

    test_live_story_matches( $db, $topic_a, $story_c, "after insert" );
    test_live_story_matches( $db, $topic_b, $story_c, "after insert" );

    $story_a = update_story( $db, $story_a );
    $story_b = update_story( $db, $story_b );
    $story_c = update_story( $db, $story_c );

    test_live_story_matches( $db, $topic_a, $story_a, "after update" );
    test_live_story_absent( $db, $topic_b, $story_a, "after update" );

    test_live_story_matches( $db, $topic_b, $story_b, "after update" );
    test_live_story_absent( $db, $topic_a, $story_b, "after update" );

    test_live_story_matches( $db, $topic_a, $story_c, "after update" );
    test_live_story_matches( $db, $topic_b, $story_c, "after update" );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_live_stories( $db );
}

main();
