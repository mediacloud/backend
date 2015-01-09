use strict;
use warnings;

# test Handler::handle_error

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use English '-no_match_vars';

use Data::Dumper;
use Test::More tests => 35;

use HTTP::HashServer;

use MediaWords::Crawler::Engine;
use MediaWords::Crawler::Fetcher;
use MediaWords::Crawler::Handler;

use MediaWords::Test::DB;
use MediaWords::Util::SQL;
use MediaWords::Util::Web;

# call the fetcher and handler on the given url.  return the download passed to the fetcher and handler.
sub fetch_and_handle_response
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

    my $engine = MediaWords::Crawler::Engine->new();

    $engine->{ dbs } = $db;

    my $fetcher = MediaWords::Crawler::Fetcher->new( $engine );
    my $handler = MediaWords::Crawler::Handler->new( $engine );

    my $response = $fetcher->fetch_download( $download );
    $handler->handle_response( $download, $response );

    return $db->find_by_id( 'downloads', $download->{ downloads_id } );
}

# verify that the given sql date is in the future
sub is_date_in_future
{
    my ( $date, $label ) = @_;

    my $epoch_date = MediaWords::Util::SQL::get_epoch_from_sql_date( $date );

    ok( $epoch_date > time(), "date '$date' from $label should be in the future" );
}

# test that Handler::handle_error deals correctly with various types of responses
sub test_errors
{
    my ( $db ) = @_;

    my $port  = '8912';
    my $pages = {
        '/foo' => '<rss version="2.0"><channel /></rss>',
        '/404' => { content => 'not found', http_status_code => 404 },
        '/500' => { content => 'server error', http_status_code => 500 },
        '/503' => { content => 'service unavailable', http_status_code => 503 },
    };

    my $hs = HTTP::HashServer->new( $port, $pages );

    $hs->start;

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, { A => { B => [ 1 ] } } );
    my $feed = $media->{ A }->{ feeds }->{ B };

    my $download_foo = fetch_and_handle_response( $db, $port, $feed, '/foo' );

    is( $download_foo->{ state }, 'success', 'foo download state' );

    my $download_404 = fetch_and_handle_response( $db, $port, $feed, '/404' );

    is( $download_404->{ state }, 'error', '404 download state' );

    my $download_500 = fetch_and_handle_response( $db, $port, $feed, '/500' );

    is( $download_500->{ state }, 'pending', '500 download state' );
    is_date_in_future( $download_500->{ download_time }, "500" );
    ok( $download_500->{ error_message } =~ /\[error_num: 1\]$/, '500 download error message includes error num' );

    my $download_503 = fetch_and_handle_response( $db, $port, $feed, '/503' );
    is( $download_503->{ state }, 'pending', '503 download 1 state' );
    is_date_in_future( $download_503->{ download_time }, "503 / 1" );

    for my $i ( 2 .. 10 )
    {
        $download_503 = fetch_and_handle_response( $db, $port, $feed, '/503', $download_503->{ downloads_id } );
        is( $download_503->{ state }, 'pending', '503 download $i state' );
        is_date_in_future( $download_503->{ download_time }, "503 / $i" );

        ok( $download_503->{ error_message } =~ /\[error_num: $i\]$/, "503 download $i error message includes error num" );
    }

    $download_503 = fetch_and_handle_response( $db, $port, $feed, '/503', $download_503->{ downloads_id } );
    is( $download_503->{ state }, 'error', '503 final download state' );

    $hs->stop;
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_errors( $db );
        }
    );
}

main();
