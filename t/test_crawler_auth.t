use strict;
use warnings;

# test http auth in crawler fetcher

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use English '-no_match_vars';

use LWP::Simple;
use HTTP::HashServer;
use Test::More tests => 6;

use MediaWords::Crawler::Engine;
use MediaWords::Crawler::Fetcher;
use MediaWords::Test::DB;
use MediaWords::Util::Config;

# call the fetcher on the given feed and return the response
sub fetch_response
{
    my ( $db, $feed, $url ) = @_;

    my $download = {
        url      => $url,
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

    return $fetcher->fetch_download( $download );
}

# test that Handler::handle_error deals correctly with various types of responses
sub test_auth
{
    my ( $db ) = @_;

    my $port = 8899;
    my $pages = { '/auth' => { auth => 'foo:bar', content => 'foo bar' } };

    my $hs = HTTP::HashServer->new( $port, $pages );

    ok( $hs, 'hashserver object returned' );

    $hs->start;

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, { A => { B => [ 1 ] } } );
    my $feed = $media->{ A }->{ feeds }->{ B };

    my $config = MediaWords::Util::Config::get_config;

    $config->{ crawler_authenticated_domains } =
      [ { domain => "localhost:$port.localhost:$port", user => 'foo', password => 'bar' } ];

    my $noauth_response = fetch_response( $db, $feed, "http://127.0.01:$port/auth" );
    my $auth_response   = fetch_response( $db, $feed, "http://localhost:$port/auth" );

    ok( !$noauth_response->is_success, "noauth response should fail" );
    is( $noauth_response->status_line, "401 Access Denied", 'noauth response should return 401' );

    ok( $auth_response->is_success, "auth response should succeed" );
    is( $auth_response->status_line, "200 OK", 'auth response should return 200' );
    is( $auth_response->content, $pages->{ '/auth' }->{ content }, "auth response content should match" );

    $hs->stop;
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_auth( $db );
        }
    );
}

main();
