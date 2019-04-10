#!/usr/bin/env prove

use strict;
use warnings;

# test feed handler errors

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More tests => 2;

use MediaWords::Test::HashServer;
use Readonly;

use MediaWords::Crawler::Engine;

Readonly my $HTTP_PORT => 8912;

# call the fetcher and handler on the given url.  return the download passed to the fetcher and handler.
sub _fetch_and_handle_response
{
    my ( $db, $port, $feed, $path, $downloads_id ) = @_;

    my $download;
    if ( !$downloads_id )
    {
        $download = {
            url      => "http://localhost:$port$path",
            host     => 'localhost',
            type     => 'feed',
            state    => 'pending',
            priority => 0,
            sequence => 1,
            feeds_id => $feed->{ feeds_id },
        };

        $download = $db->create( 'downloads', $download );
    }
    else
    {
        $download = $db->find_by_id( 'downloads', $downloads_id );
    }

    my $handler = MediaWords::Crawler::Engine::handler_for_download( $db, $download );

    my $response = $handler->fetch_download( $db, $download );
    $handler->handle_response( $db, $download, $response );

    return $db->find_by_id( 'downloads', $download->{ downloads_id } );
}

# Test what happens with an invalid RSS feed
sub test_invalid_feed($)
{
    my ( $db ) = @_;

    my $pages = {

        # Feed with XML error
        '/foo' => '<rss version="2.0"><kim_kardashian></rss>',
    };

    my $hs = MediaWords::Test::HashServer->new( $HTTP_PORT, $pages );

    $hs->start;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack( $db, { A => { B => [ 1 ] } } );
    my $feed = $media->{ A }->{ feeds }->{ B };

    my $download = _fetch_and_handle_response( $db, $HTTP_PORT, $feed, '/foo' );

    is( $download->{ state }, 'feed_error', 'Invalid feed download state' );
    like( $download->{ error_message }, qr/Unable to parse feed/, "Invalid feed download error" );

    $hs->stop;
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_invalid_feed( $db );
}

main();
