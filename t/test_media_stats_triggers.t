#!/usr/bin/env perl

use strict;
use warnings;

# test MediaWords::DBI::Stories::is_new

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Test::More;
use Time::HiRes;

BEGIN
{
    use_ok( 'MediaWords::DB' );
    use_ok( 'MediaWords::Test::DB' );
    use_ok( 'MediaWords::Util::SQL' );
}

sub insert_story
{
    my ( $db, $medium ) = @_;

    my $feed = ( values( %{ $medium->{ feeds } } ) )[ 0 ];

    MediaWords::Test::DB::create_test_story( $db, Time::HiRes::time, $feed );
}

sub test_media_stat
{
    my ( $test_label, $db, $medium, $publish_date, $expected_num_stories, $expected_num_sentences ) = @_;

    my $full_test_label = "$test_label [$medium->{ name } / $publish_date]";

    my $stats = $db->query( <<END, $medium->{ media_id }, $publish_date )->hash;
select * from media_stats where media_id = ? and stat_date = ?
END

    my $got_num_stories   = $stats ? $stats->{ num_stories }   : 0;
    my $got_num_sentences = $stats ? $stats->{ num_sentences } : 0;

    is( $got_num_stories,   $expected_num_stories,   "$full_test_label - num_stories" );
    is( $got_num_sentences, $expected_num_sentences, "$full_test_label - num_sentences" );
}

sub delete_latest_story
{
    my ( $db, $medium ) = @_;

    $db->query( <<END, $medium->{ media_id } );
delete from stories where stories_id in (
    select stories_id from stories where media_id = ? order by stories_id desc limit 1
)
END

}

sub insert_story_sentences
{
    my ( $db, $story, $num_sentences ) = @_;

    for my $i ( 1 .. $num_sentences )
    {
        my $ss = {
            stories_id      => $story->{ stories_id },
            sentence_number => $i,
            sentence        => 'foo bar baz',
            media_id        => $story->{ media_id },
            publish_date    => $story->{ publish_date }
        };
        $db->create( 'story_sentences', $ss );
    }
}

sub delete_story_sentences
{
    my ( $db, $story, $num ) = @_;

    $db->query( <<END, $story->{ stories_id }, $num );
delete from story_sentences where story_sentences_id in (
    select story_sentences_id from story_sentences where stories_id = ? limit ?
)
END

}

sub update_story_date
{
    my ( $db, $story, $new_date ) = @_;

    $db->query( "update stories set publish_date = ? where stories_id = ?", $new_date, $story->{ stories_id } );

}

sub run_tests
{
    my ( $db ) = @_;

    my $data = {
        A => {
            B => [ 1, 2, 3 ],
            C => [ 4, 5, 6 ]
        },
        D => { E => [ 7, 8, 9 ] }
    };

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, $data );

    my $publish_date = $media->{ 1 }->{ publish_date };

    test_media_stat( 'initial A', $db, $media->{ A }, $publish_date, 6, 0 );
    test_media_stat( 'initial D', $db, $media->{ D }, $publish_date, 3, 0 );

    insert_story( $db, $media->{ A } );
    test_media_stat( 'insert story A', $db, $media->{ A }, $publish_date, 7, 0 );
    test_media_stat( 'insert story A', $db, $media->{ D }, $publish_date, 3, 0 );

    insert_story( $db, $media->{ D } );
    test_media_stat( 'insert story D #1', $db, $media->{ A }, $publish_date, 7, 0 );
    test_media_stat( 'insert story D #1', $db, $media->{ D }, $publish_date, 4, 0 );

    insert_story( $db, $media->{ D } );
    test_media_stat( 'insert story D #2', $db, $media->{ A }, $publish_date, 7, 0 );
    test_media_stat( 'insert story D #2', $db, $media->{ D }, $publish_date, 5, 0 );

    delete_latest_story( $db, $media->{ A } );
    test_media_stat( 'delete story A', $db, $media->{ A }, $publish_date, 6, 0 );
    test_media_stat( 'delete story A', $db, $media->{ D }, $publish_date, 5, 0 );

    delete_latest_story( $db, $media->{ D } );
    test_media_stat( 'delete story D', $db, $media->{ A }, $publish_date, 6, 0 );
    test_media_stat( 'delete story D', $db, $media->{ D }, $publish_date, 4, 0 );

    insert_story_sentences( $db, $media->{ 2 }, 1 );
    test_media_stat( 'insert ss A #1', $db, $media->{ A }, $publish_date, 6, 1 );
    test_media_stat( 'insert ss A #1', $db, $media->{ D }, $publish_date, 4, 0 );

    insert_story_sentences( $db, $media->{ 1 }, 5 );
    test_media_stat( 'insert ss A #2', $db, $media->{ A }, $publish_date, 6, 6 );
    test_media_stat( 'insert ss A #2', $db, $media->{ D }, $publish_date, 4, 0 );

    insert_story_sentences( $db, $media->{ 8 }, 21 );
    test_media_stat( 'insert ss D', $db, $media->{ A }, $publish_date, 6, 6 );
    test_media_stat( 'insert ss D', $db, $media->{ D }, $publish_date, 4, 21 );

    delete_story_sentences( $db, $media->{ 1 }, 1 );
    test_media_stat( 'delete ss A', $db, $media->{ A }, $publish_date, 6, 5 );
    test_media_stat( 'delete ss A', $db, $media->{ D }, $publish_date, 4, 21 );

    delete_story_sentences( $db, $media->{ 8 }, 10 );
    test_media_stat( 'delete ss D', $db, $media->{ A }, $publish_date, 6, 5 );
    test_media_stat( 'delete ss D', $db, $media->{ D }, $publish_date, 4, 11 );

    my $new_date = MediaWords::Util::SQL::increment_day( $publish_date, 30 );

    update_story_date( $db, $media->{ 8 }, $new_date );
    test_media_stat( 'update date D', $db, $media->{ A }, $publish_date, 6, 5 );
    test_media_stat( 'update date D', $db, $media->{ D }, $publish_date, 3, 0 );
    test_media_stat( 'update date D', $db, $media->{ A }, $new_date,     0, 0 );
    test_media_stat( 'update date D', $db, $media->{ D }, $new_date,     1, 11 );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            use Encode;
            my ( $db ) = @_;

            run_tests( $db );
        }
    );

    done_testing();
}

main();
