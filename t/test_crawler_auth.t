use strict;
use warnings;

# test http auth in crawler fetcher

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use English '-no_match_vars';

use MediaWords::Test::HTTP::HashServer;
use Test::More tests => 6;

use MediaWords::Crawler::Engine;
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

    my $handler = MediaWords::Crawler::Engine::handler_for_download( $db, $download );
    return $handler->fetch_download( $db, $download );
}

# test that Handler::_handle_error() deals correctly with various types of responses
sub test_auth
{
    my ( $db ) = @_;

    my $port = 8899;
    my $pages = { '/auth' => { auth => 'foo:bar', content => 'foo bar' } };

    my $hs = MediaWords::Test::HTTP::HashServer->new( $port, $pages );

    ok( $hs, 'hashserver object returned' );

    $hs->start;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack( $db, { A => { B => [ 1 ] } } );
    my $feed = $media->{ A }->{ feeds }->{ B };

    my $config     = MediaWords::Util::Config::get_config;
    my $new_config = python_deep_copy( $config );

    $new_config->{ mediawords }->{ crawler_authenticated_domains } =
      [ { domain => 'localhost.localhost', user => 'foo', password => 'bar' } ];
    MediaWords::Util::Config::set_config( $new_config );

    my $noauth_response = fetch_response( $db, $feed, "http://127.0.0.1:$port/auth" );
    my $auth_response   = fetch_response( $db, $feed, "http://localhost:$port/auth" );

    ok( !$noauth_response->is_success, "noauth response should fail" );
    is( $noauth_response->code, 401, 'noauth response should return 401' );

    ok( $auth_response->is_success, "auth response should succeed" );
    is( $auth_response->code, 200, 'auth response should return 200' );
    is( $auth_response->decoded_content, $pages->{ '/auth' }->{ content }, "auth response content should match" );

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
