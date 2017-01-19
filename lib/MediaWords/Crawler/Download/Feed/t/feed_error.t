use strict;
use warnings;

# test feed handler errors

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More tests => 4;

use HTTP::HashServer;
use Readonly;

use MediaWords::Crawler::Engine;
use MediaWords::Test::DB;

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

    my $hs = HTTP::HashServer->new( $HTTP_PORT, $pages );

    $hs->start;

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, { A => { B => [ 1 ] } } );
    my $feed = $media->{ A }->{ feeds }->{ B };

    my $download = _fetch_and_handle_response( $db, $HTTP_PORT, $feed, '/foo' );

    is( $download->{ state }, 'feed_error', 'Invalid feed download state' );
    like( $download->{ error_message }, qr/Unable to parse feed/, "Invalid feed download error" );

    $hs->stop;
}

# Test what happens when 'do_not_process_feeds' is set
sub test_do_not_process_feeds($)
{
    my ( $db ) = @_;

    # Temporarily set 'do_not_process_feeds'
    my $config     = MediaWords::Util::Config::get_config;
    my $new_config = make_python_variable_writable( $config );

    my $orig_do_not_process_feeds = $config->{ mediawords }->{ do_not_process_feeds };
    $new_config->{ mediawords }->{ do_not_process_feeds } = 'yes';
    MediaWords::Util::Config::set_config( $new_config );

    my $pages = { '/foo' => '<rss version="2.0"><channel /></rss>', };

    my $hs = HTTP::HashServer->new( $HTTP_PORT, $pages );

    $hs->start;

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, { A => { B => [ 1 ] } } );
    my $feed = $media->{ A }->{ feeds }->{ B };

    my $download = _fetch_and_handle_response( $db, $HTTP_PORT, $feed, '/foo' );

    is( $download->{ state }, 'feed_error', '"do_not_process_feeds" download state' );
    like( $download->{ error_message }, qr/do_not_process_feeds/, "'do_not_process_feeds' download error" );

    $hs->stop;

    $new_config->{ mediawords }->{ do_not_process_feeds } = $orig_do_not_process_feeds;
    MediaWords::Util::Config::set_config( $new_config );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_invalid_feed( $db );
        }
    );

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_do_not_process_feeds( $db );
        }
    );
}

main();
