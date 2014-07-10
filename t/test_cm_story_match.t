#!/usr/bin/env perl

use strict;
use warnings;

# test MediaWords::CM::Mine::get_matching_story_from_db

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use English '-no_match_vars';

use Test::More tests => 12;
use Test::Deep;

BEGIN
{
    use_ok( 'MediaWords::DB' );
    use_ok( 'MediaWords::Test::DB' );
    use_ok( 'MediaWords::CM::Mine' );
}

sub test_match
{
    my ( $db, $url, $redirect_url, $expected_story, $description ) = @_;

    my $link = { url => $url, redirect_url => $redirect_url };

    my $got_story = MediaWords::CM::Mine::get_matching_story_from_db( $db, $link );

    is( $got_story->{ stories_id }, $expected_story->{ stories_id }, $description );
}

sub test_story_matches
{
    my ( $db ) = @_;

    my $medium_media_id = {
        name        => "media id",
        url         => "http://test/media/id",
        moderated   => 't',
        feeds_added => 't'
    };
    $medium_media_id = $db->create( 'media', $medium_media_id );

    my $medium_dup_target = {
        name        => "dup target",
        url         => "http://test/dup/target",
        moderated   => 't',
        feeds_added => 't'
    };
    $medium_dup_target = $db->create( 'media', $medium_dup_target );

    my $medium_dup_source = {
        name         => "dup source",
        url          => "http://test/dup/source",
        moderated    => 't',
        feeds_added  => 't',
        dup_media_id => $medium_dup_target->{ media_id }
    };
    $medium_dup_source = $db->create( 'media', $medium_dup_source );

    my $medium_domain = {
        name        => "domain match",
        url         => "http://foo.domainmatch.com/bar",
        moderated   => 't',
        feeds_added => 't'
    };
    $medium_domain = $db->create( 'media', $medium_domain );

    my $medium_ignore = {
        name        => "ignore",
        url         => "http://test/ignore",
        moderated   => 't',
        feeds_added => 't'
    };
    $medium_ignore = $db->create( 'media', $medium_ignore );

    my $story_media_id = {
        media_id      => $medium_media_id->{ media_id },
        url           => 'http://story/media_id',
        guid          => 'guid://story/media_id',
        title         => 'story dup target',
        description   => 'description dup target',
        publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 100000 ),
        collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 200000 ),
        full_text_rss => 't'
    };
    $story_media_id = $db->create( 'stories', $story_media_id );

    my $story_dup_target = {
        media_id      => $medium_dup_target->{ media_id },
        url           => 'http://story/dup_target',
        guid          => 'guid://story/dup_target',
        title         => 'story dup target',
        description   => 'description dup target',
        publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 100000 ),
        collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 200000 ),
        full_text_rss => 't'
    };
    $story_dup_target = $db->create( 'stories', $story_dup_target );

    my $story_dup_source = {
        media_id      => $medium_dup_source->{ media_id },
        url           => 'http://story/dup_source',
        guid          => 'guid://story/dup_source',
        title         => 'story dup source',
        description   => 'description dup source',
        publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 100000 ),
        collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 200000 ),
        full_text_rss => 't'
    };
    $story_dup_source = $db->create( 'stories', $story_dup_source );

    my $story_domain = {
        media_id      => $medium_domain->{ media_id },
        url           => 'http://story/domain',
        guid          => 'guid://story/domain',
        title         => 'story domain',
        description   => 'description domain',
        publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 100000 ),
        collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 200000 ),
        full_text_rss => 't'
    };
    $story_domain = $db->create( 'stories', $story_domain );

    my $story_ignore = {
        media_id      => $medium_ignore->{ media_id },
        url           => 'http://story/ignore',
        guid          => 'guid://story/ignore',
        title         => 'story ignore',
        description   => 'description ignore',
        publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 100000 ),
        collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 200000 ),
        full_text_rss => 't'
    };
    $story_ignore = $db->create( 'stories', $story_ignore );

    test_match( $db, 'http://non/existent',     undef,                     undef,             'non existent story' );
    test_match( $db, 'http://story/dup_target', undef,                     $story_dup_target, 'simple url match' );
    test_match( $db, 'http://STORY/dup_target', undef,                     $story_dup_target, 'lowercase url match' );
    test_match( $db, 'http://non/existent',     'http://story/dup_target', $story_dup_target, 'simple redirect url match' );
    test_match( $db, 'http://non/existent', 'http://STORY/dup_target', $story_dup_target, 'lowercase redirect url match' );

    $db->query( "update stories set url = 'http://story/dup_target'" );
    test_match( $db, 'http://story/dup_target', undef, $story_dup_target, 'dup target preference' );

    my $story_url = 'http://story/dup_source';
    $db->query( "update stories set url = ? where media_id > ?", $story_url, $medium_dup_target->{ media_id } );
    test_match( $db, $story_url, undef, $story_dup_source, 'dup source preference' );

    $story_url = 'http://foobar.domainmatch.com/foo/bar/baz';
    $db->query( "update stories set url = ? where media_id > ?", $story_url, $medium_dup_source->{ media_id } );
    test_match( $db, $story_url, undef, $story_domain, 'domain match' );

    $story_url = 'http://story/media_id';
    $db->query( "update media set dup_media_id = null" );
    $db->query( "update stories set url = ?", $story_url );
    test_match( $db, $story_url, undef, $story_media_id, 'media_id' );

}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            use Encode;
            my ( $db ) = @_;

            test_story_matches( $db );
        }
    );
}

main();
