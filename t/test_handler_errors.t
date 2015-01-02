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

use HTTP::HashServer;
use Test::More tests => 14;

use MediaWords::Crawler::Engine;
use MediaWords::Crawler::Fetcher;
use MediaWords::Crawler::Handler;

use MediaWords::Test::DB;
use MediaWords::Util::SQL;
use MediaWords::Util::Web;

# call the fetcher and handler on the given url.  return the download passed to the fetcher and handler.
sub fetch_and_handle_response
{
    my ( $db, $port, $feed, $path ) = @_;

    my $download = {
        url      => "http://localhost:$port$path",
        host     => 'localhost',
        type     => 'feed',
        state    => 'pending',
        priority => 0,
        sequence => 1,
        feeds_id => $feed->{ feeds_id },
    };

    $download = $db->create( 'downloads', $download );

    my $engine = MediaWords::Crawler::Engine->new();

    $engine->{ dbs } = $db;
    $engine->fetcher_number( 1 );

    my $fetcher = MediaWords::Crawler::Fetcher->new( $engine );
    my $handler = MediaWords::Crawler::Handler->new( $engine );

    my $response = $fetcher->fetch_download( $download );
    $handler->handle_response( $download, $response );

    return $db->find_by_id( 'downloads', $download->{ downloads_id } );
}

# test that Handler::handle_error deals correctly with various types of responses
sub test_errors
{
    my ( $db ) = @_;

    my $port  = '8912';
    my $pages = {
        '/foo' => 'foo',
        '/404' => { content => 'not found', http_status_code => 404 },
        '/500' => { content => 'server error', http_status_code => 500 },
        '/503' => { content => 'service unavailable', http_status_code => 503 },
    };

    my $hs = HTTP::HashServer->new( $port, $pages );

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, { A => { B => [ 1 ] } } );
    my $feed = $media->{ A }->{ feeds }->{ B };

    my $download_foo = fetch_and_handle_response( $db, $port, $feed, '/foo' );

    is( $download_foo->{ state }, 'success', 'foo download state' );

    my $download_404 = fetch_and_handle_response( $db, $port, $feed, '/404' );

    is( $download_404->{ state }, 'error', '404 download state' );

    my $download_500 = fetch_and_handle_response( $db, $port, $feed, '/500' );

    is( $download_500->{ state }, 'pending', '500 download state' );
    ok( $download_500->{ download_time } gt MediaWords::Util::SQL::sql_now, '500 download time in future' );
    ok( $download_500->{ error_message } =~ /[error_num: 1]$/, '500 download error message includes error num' );

    for my $i ( 1 .. 10 )
    {
        my $download_503 = fetch_and_handle_response( $db, $port, $feed, '/503' );
        is( $download_503->{ state }, 'pending', '503 download $i state' );
        ok( $download_503->{ download_time } gt MediaWords::Util::SQL::sql_now, '503 download $i time in future' );
        ok( $download_503->{ error_message } =~ /[error_num: $i]$/, '503 download $i error message includes error num' );
    }

    my $download_503 = fetch_and_handle_response( $db, $port, $feed, '/503' );
    is( $download_503->{ state }, 'error', '503 final download state' );
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
