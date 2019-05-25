#!/usr/bin/env perl

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::Crawler::Engine;
use MediaWords::Test::HashServer;
use MediaWords::Test::DB::Create;

sub test_run_fetcher
{
    my ( $db ) = @_;

    my $port  = 23456;
    my $pages = {
        '/foo' => 'foo',
        '/bar' => 'bar'
    };

    my $hs = MediaWords::Test::HashServer->new( $port, $pages );

    $hs->start();

    my $medium = MediaWords::Test::DB::Create::create_test_medium( $db, 'foo' );
    my $feed = MediaWords::Test::DB::Create::create_test_feed( $db, 'foo', $medium );
    my $story = MediaWords::Test::DB::Create::create_test_story( $db, 'foo', $feed );

    my $download = {
        state      => 'pending',
        feeds_id   => $feed->{ feeds_id },
        stories_id => $story->{ stories_id },
        type       => 'content',
        sequence   => 1,
        priority   => 1,
        url        => "http://localhost:$port/foo",
        host       => 'localhost'
    };
    $download = $db->create( 'downloads', $download );

    $db->query( "insert into queued_downloads ( downloads_id ) select downloads_id from downloads" );

    my $crawler = MediaWords::Crawler::Engine->new();

    $crawler->run_fetcher( 1 );

    my $download = $db->find_by_id( 'downloads', $download->{ downloads_id } );

    is( $download->{ state }, 'success' );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_run_fetcher( $db );

    done_testing();
}

main();
