use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::Deep;
use Test::More tests => 139;

use Encode;
use File::Temp qw/ tempdir tempfile /;
use File::Slurp;
use HTTP::Status qw(:constants);
use Readonly;
use Data::Dumper;
use File::ReadBackwards;
use URI;
use URI::Escape;
use URI::QueryParam;

use MediaWords::Util::Config::Common;
use MediaWords::Util::ParseJSON;
use MediaWords::Util::Web;
use MediaWords::Util::Text;
use MediaWords::Test::HashServer;
use MediaWords::Test::URLs;

my Readonly $TEST_HTTP_SERVER_PORT = 9998;
my Readonly $TEST_HTTP_SERVER_URL  = 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

sub test_get()
{
    eval {
        my $ua = MediaWords::Util::Web::UserAgent->new();
        $ua->get( undef );
    };
    ok( $@, 'Undefined URL' );

    eval {
        my $ua = MediaWords::Util::Web::UserAgent->new();
        $ua->get( 'gopher://gopher.floodgap.com/0/v2/vstat' );
    };
    ok( $@, 'Non-HTTP(S) URL' );

    # Basic GET
    my $pages = { '/test' => 'Hello!', };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get( "$TEST_HTTP_SERVER_URL/test" );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/test' );
    is( $response->decoded_content(), 'Hello!' );
}

sub test_get_user_agent_from_headers()
{
    # User-Agent: and From: headers
    my $pages = {
        '/user-agent-from-headers' => {
            callback => sub {
                my ( $request ) = @_;

                my $response = '';

                $response .= "HTTP/1.0 200 OK\r\n";
                $response .= "Content-Type: application/json; charset=UTF-8\r\n";
                $response .= "\r\n";
                $response .= MediaWords::Util::ParseJSON::encode_json(
                    {
                        'user-agent' => $request->header( 'User-Agent' ),
                        'from'       => $request->header( 'From' ),
                    }
                );

                return $response;
            }
        }
    };
    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get( "$TEST_HTTP_SERVER_URL/user-agent-from-headers" );

    $hs->stop();

    ok( $response->is_success() );
    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/user-agent-from-headers' );

    my $expected_user_agent = 'mediawords bot (http://cyber.law.harvard.edu)';
    my $expected_from       = 'mediawords@cyber.law.harvard.edu';

    my $decoded_json = MediaWords::Util::ParseJSON::decode_json( $response->decoded_content() );
    cmp_deeply(
        $decoded_json,
        {
            'user-agent' => $expected_user_agent,
            'from'       => $expected_from,
        }
    );
}

sub test_get_not_found()
{
    # HTTP redirects
    my $pages = {
        '/does-not-exist' => {
            callback => sub {
                my ( $request ) = @_;

                my $response = '';

                $response .= "HTTP/1.0 404 Not Found\r\n";
                $response .= "Content-Type: text/html; charset=UTF-8\r\n";
                $response .= "\r\n";
                $response .= "I do not exist.";

                return $response;
            }
        }
    };
    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get( "$TEST_HTTP_SERVER_URL/does-not-exist" );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/does-not-exist' );
    ok( !$response->is_success() );
    is( $response->decoded_content(), 'I do not exist.' );
}

sub test_get_valid_utf8_content()
{
    # Valid UTF-8 content
    my $pages = {
        '/valid-utf-8' => {
            header  => 'Content-Type: text/plain; charset=UTF-8',
            content => '¡ollǝɥ',
        },
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get( "$TEST_HTTP_SERVER_URL/valid-utf-8" );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/valid-utf-8' );
    is( $response->decoded_content(), '¡ollǝɥ' );
}

sub test_get_invalid_utf8_content()
{
    # Invalid UTF-8 content
    my $pages = {
        '/invalid-utf-8' => {
            header  => 'Content-Type: text/plain; charset=UTF-8',
            content => "\xf0\x90\x28\xbc",
        },
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get( "$TEST_HTTP_SERVER_URL/invalid-utf-8" );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/invalid-utf-8' );

    # https://en.wikipedia.org/wiki/Specials_(Unicode_block)#Replacement_character
    my $replacement_character = "\x{FFFD}";
    ok(
        # OS X:
        $response->decoded_content() eq "$replacement_character\x28$replacement_character" or

          # Ubuntu:
          $response->decoded_content() eq "$replacement_character$replacement_character\x28$replacement_character"
    );
}

sub test_get_non_utf8_content()
{
    # Non-UTF-8 content
    use bytes;

    my $pages = {
        '/non-utf-8' => {
            header  => 'Content-Type: text/plain; charset=iso-8859-13',
            content => "\xd0auk\xf0tai po piet\xf8.",
        },
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get( "$TEST_HTTP_SERVER_URL/non-utf-8" );

    $hs->stop();

    no bytes;

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/non-utf-8' );
    is( $response->decoded_content(), 'Šaukštai po pietų.' );
}

sub test_get_max_size()
{
    my $test_content = MediaWords::Util::Text::random_string( 1024 * 10 );
    my $max_size     = length( $test_content ) / 10;
    my $pages        = { '/max-download-side' => $test_content, };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_max_size( $max_size );
    is( $ua->max_size(), $max_size );

    my $response = $ua->get( "$TEST_HTTP_SERVER_URL/max-download-side" );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/max-download-side' );

    # LWP::UserAgent truncates the response but still reports it as successful
    ok( $response->is_success() );
    ok( length( $response->decoded_content() ) >= $max_size );
    ok( length( $response->decoded_content() ) <= length( $test_content ) );
}

sub test_get_max_redirect()
{
    my $max_redirect = 3;
    my $pages        = {
        '/1' => { redirect => '/2' },
        '/2' => { redirect => '/3' },
        '/3' => { redirect => '/4' },
        '/4' => { redirect => '/5' },
        '/5' => { redirect => '/6' },
        '/6' => { redirect => '/7' },
        '/7' => { redirect => '/8' },
        '/8' => "Shouldn't be able to get to this one.",
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_max_redirect( $max_redirect );
    is( $ua->max_redirect(), $max_redirect );

    my $response = $ua->get( "$TEST_HTTP_SERVER_URL/1" );

    $hs->stop();

    ok( !$response->is_success() );
}

sub test_get_request_headers()
{
    my $pages = {
        '/test-custom-header' => {
            callback => sub {
                my ( $request ) = @_;

                my $response = '';

                $response .= "HTTP/1.0 200 OK\r\n";
                $response .= "Content-Type: application/json; charset=UTF-8\r\n";
                $response .= "\r\n";
                $response .=
                  MediaWords::Util::ParseJSON::encode_json( { 'custom-header' => $request->header( 'X-Custom-Header' ), } );

                return $response;
            }
        }
    };
    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua  = MediaWords::Util::Web::UserAgent->new();
    my $url = "$TEST_HTTP_SERVER_URL/test-custom-header";

    my $request = MediaWords::Util::Web::UserAgent::Request->new( 'GET', $url );
    $request->set_header( 'X-Custom-Header', 'foo' );

    my $response = $ua->request( $request );

    ok( $response->is_success() );
    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/test-custom-header' );

    my $decoded_json = MediaWords::Util::ParseJSON::decode_json( $response->decoded_content() );
    cmp_deeply( $decoded_json, { 'custom-header' => 'foo' } );

    $hs->stop();
}

sub test_get_response_status()
{
    my $pages = {
        '/test' => {
            callback => sub {
                my ( $request ) = @_;

                my $response = '';

                $response .= "HTTP/1.0 418 Jestem czajniczek\r\n";
                $response .= "Content-Type: text/html; charset=UTF-8\r\n";
                $response .= "\r\n";
                $response .= "☕";

                return $response;
            }
        }
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get( "$TEST_HTTP_SERVER_URL/test" );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/test' );
    is( $response->decoded_content(), '☕' );

    # HTTP status cod and message
    is( $response->code(),        418 );
    is( $response->message(),     'Jestem czajniczek' );
    is( $response->status_line(), '418 Jestem czajniczek' );
}

sub test_get_response_headers()
{
    my $pages = {
        '/test' => {
            header  => "Content-Type: text/plain; charset=UTF-8\r\nX-Media-Cloud: mediacloud",
            content => "pnolɔ ɐıpǝɯ",
        }
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get( "$TEST_HTTP_SERVER_URL/test" );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/test' );
    is( $response->decoded_content(), 'pnolɔ ɐıpǝɯ' );

    # Uppercase / lowercase headers
    is( $response->header( 'X-Media-Cloud' ), 'mediacloud' );
    is( $response->header( 'x-media-cloud' ), 'mediacloud' );
}

sub test_get_response_content_type()
{
    my $pages = {
        '/test' => {
            header  => "Content-Type: application/xhtml+xml; charset=UTF-8",
            content => "pnolɔ ɐıpǝɯ",
        }
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get( "$TEST_HTTP_SERVER_URL/test" );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/test' );
    is( $response->decoded_content(), 'pnolɔ ɐıpǝɯ' );

    is( $response->content_type(), 'application/xhtml+xml' );
}

sub test_get_blacklisted_url()
{
    my $tempdir = tempdir( CLEANUP => 1 );
    ok( -e $tempdir );

    my $whitelist_temp_file = $tempdir . '/whitelisted_url_opened.txt';
    my $blacklist_temp_file = $tempdir . '/blacklisted_url_opened.txt';
    ok( !-e $whitelist_temp_file );
    ok( !-e $blacklist_temp_file );

    my $pages = {
        '/whitelisted' => {
            callback => sub {
                my ( $request ) = @_;

                open( my $fh, '>', $whitelist_temp_file );
                print $fh "Whitelisted URL has been fetched.";
                close $fh;

                my $response = '';

                $response .= "HTTP/1.0 200 OK\r\n";
                $response .= "Content-Type: text/plain\r\n";
                $response .= "\r\n";
                $response .= "Whitelisted page (should be fetched).";

                return $response;
            }
        },
        '/blacklisted' => {
            callback => sub {
                my ( $request ) = @_;

                open( my $fh, '>', $blacklist_temp_file );
                print $fh "Blacklisted URL has been fetched.";
                close $fh;

                my $response = '';

                $response .= "HTTP/1.0 200 OK\r\n";
                $response .= "Content-Type: text/plain\r\n";
                $response .= "\r\n";
                $response .= "Blacklisted page (should not be fetched).";

                return $response;
            }
        },
    };

    my $whitelisted_url = $TEST_HTTP_SERVER_URL . "/whitelisted";
    my $blacklisted_url = $TEST_HTTP_SERVER_URL . "/blacklisted";

    {
        package BlacklistedURLUserAgentConfig;

        use strict;
        use warnings;

        use base 'MediaWords::Util::Config::Common::UserAgent';

        sub blacklist_url_pattern()
        {
            return "$blacklisted_url";
        }

        1;
    }

    my $default_ua_config = MediaWords::Util::Config::Common::user_agent();
    my $blacklisted_url_ua_config = BlacklistedURLUserAgentConfig->new( $default_ua_config );
    my $ua                   = MediaWords::Util::Web::UserAgent->new( $blacklisted_url_ua_config );

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $blacklisted_response = $ua->get( $blacklisted_url );
    my $whitelisted_response = $ua->get( $whitelisted_url );

    $hs->stop();

    ok( !$blacklisted_response->is_success() );
    ok( $blacklisted_response->error_is_client_side() );
    isnt_urls( $blacklisted_response->request()->url(), $blacklisted_url );

    ok( $whitelisted_response->is_success() );
    is_urls( $whitelisted_response->request()->url(), $whitelisted_url );

    ok( -e $whitelist_temp_file );
    ok( !-e $blacklist_temp_file );
}

sub test_get_http_auth()
{
    my $pages = {
        '/auth' => {
            auth    => 'username1:password2',
            content => 'Authenticated!',
        }
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua = MediaWords::Util::Web::UserAgent->new();

    {
        # No auth
        my $no_auth_url      = $TEST_HTTP_SERVER_URL . "/auth";
        my $no_auth_response = $ua->get( $no_auth_url );
        ok( !$no_auth_response->is_success() );
        is( $no_auth_response->code(), HTTP_UNAUTHORIZED );
    }

    {
        # Invalid auth in URL
        my $invalid_auth_url =
          'http://incorrect_username1:incorrect_password2@localhost:' . $TEST_HTTP_SERVER_PORT . "/auth";
        my $invalid_auth_response = $ua->get( $invalid_auth_url );
        ok( !$invalid_auth_response->is_success() );
        is( $invalid_auth_response->code(), HTTP_UNAUTHORIZED );
    }

    {
        # Valid auth in URL
        my $valid_auth_url      = 'http://username1:password2@localhost:' . $TEST_HTTP_SERVER_PORT . "/auth";
        my $valid_auth_response = $ua->get( $valid_auth_url );
        ok( $valid_auth_response->is_success() );
        is( $valid_auth_response->code(),            HTTP_OK );
        is( $valid_auth_response->decoded_content(), 'Authenticated!' );
    }

    my $base_auth_url = $TEST_HTTP_SERVER_URL . "/auth";

    {
        # Invalid auth in request
        my $invalid_auth_request = MediaWords::Util::Web::UserAgent::Request->new( 'GET', $base_auth_url );
        $invalid_auth_request->set_authorization_basic( 'incorrect_username1', 'incorrect_password2' );
        my $invalid_auth_response = $ua->request( $invalid_auth_request );
        ok( !$invalid_auth_response->is_success() );
        is( $invalid_auth_response->code(), HTTP_UNAUTHORIZED );
    }

    {
        # Valid auth in request
        my $valid_auth_request = MediaWords::Util::Web::UserAgent::Request->new( 'GET', $base_auth_url );
        $valid_auth_request->set_authorization_basic( 'username1', 'password2' );
        my $valid_auth_response = $ua->request( $valid_auth_request );
        ok( $valid_auth_response->is_success() );
        is( $valid_auth_response->code(),            HTTP_OK );
        is( $valid_auth_response->decoded_content(), 'Authenticated!' );
    }

    $hs->stop();
}

sub test_get_authenticated_domains()
{
    # This is what get_url_distinctive_domain() returns for whatever reason
    my $domain   = 'localhost.localhost';
    my $username = 'username1';
    my $password = 'password2';

    my $pages = {
        '/auth' => {
            auth    => "$username:$password",
            content => 'Authenticated!',
        }
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $base_auth_url = $TEST_HTTP_SERVER_URL . "/auth";

    {
        {
            package NoAuthUserAgentConfig;

            use strict;
            use warnings;

            use base 'MediaWords::Util::Config::Common::UserAgent';

            sub authenticated_domains()
            {
                return [];
            }

            1;
        }

        my $default_ua_config = MediaWords::Util::Config::Common::user_agent();
        my $no_auth_ua_config = NoAuthUserAgentConfig->new( $default_ua_config );
        my $ua                = MediaWords::Util::Web::UserAgent->new( $no_auth_ua_config );

        my $no_auth_response = $ua->get( $base_auth_url );
        ok( !$no_auth_response->is_success() );
        is( $no_auth_response->code(), HTTP_UNAUTHORIZED );
    }

    {
        {
            package IncorrectDomain;

            use strict;
            use warnings;

            sub new($)
            {
                my ( $class ) = @_;

                my $self = {};
                bless $self, $class;

                return $self;
            }

            sub domain() { return $domain; }
            sub username() { return 'incorrect_username1'; }
            sub password() { return 'incorrect_password2'; }

            1;
        }

        {
            package IncorrectAuthUserAgentConfig;

            use strict;
            use warnings;

            use base 'MediaWords::Util::Config::Common::UserAgent';

            sub authenticated_domains() { return [ IncorrectDomain->new() ]; }

            1;
        }

        my $default_ua_config = MediaWords::Util::Config::Common::user_agent();
        my $incorrect_auth_ua_config = IncorrectAuthUserAgentConfig->new( $default_ua_config );
        my $ua                = MediaWords::Util::Web::UserAgent->new( $incorrect_auth_ua_config );

        my $invalid_auth_response = $ua->get( $base_auth_url );
        ok( !$invalid_auth_response->is_success() );
        is( $invalid_auth_response->code(), HTTP_UNAUTHORIZED );
    }

    {
        {
            package CorrectDomain;

            use strict;
            use warnings;

            sub new($)
            {
                my ( $class ) = @_;

                my $self = {};
                bless $self, $class;

                return $self;
            }

            sub domain() { return $domain; }
            sub username() { return $username; }
            sub password() { return $password; }

            1;
        }

        {
            package CorrectAuthUserAgentConfig;

            use strict;
            use warnings;

            use base 'MediaWords::Util::Config::Common::UserAgent';

            sub authenticated_domains() { return [ CorrectDomain->new() ]; }

            1;
        }

        my $default_ua_config = MediaWords::Util::Config::Common::user_agent();
        my $correct_auth_ua_config = CorrectAuthUserAgentConfig->new( $default_ua_config );
        my $ua                = MediaWords::Util::Web::UserAgent->new( $correct_auth_ua_config );

        my $valid_auth_response = $ua->get( $base_auth_url );
        ok( $valid_auth_response->is_success() );
        is( $valid_auth_response->code(),            HTTP_OK );
        is( $valid_auth_response->decoded_content(), 'Authenticated!' );
    }

    $hs->stop();
}

sub test_get_follow_http_html_redirects_http()
{
    my $ua = MediaWords::Util::Web::UserAgent->new();

    eval { $ua->get_follow_http_html_redirects( undef ); };
    ok( $@, 'Undefined URL' );

    eval { $ua->get_follow_http_html_redirects( 'gopher://gopher.floodgap.com/0/v2/vstat' ); };
    ok( $@, 'Non-HTTP(S) URL' );

    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # HTTP redirects
    my $pages = {
        '/first'  => { redirect => '/second',                        http_status_code => HTTP_MOVED_PERMANENTLY },
        '/second' => { redirect => $TEST_HTTP_SERVER_URL . '/third', http_status_code => HTTP_FOUND },
        '/third'  => { redirect => '/fourth',                        http_status_code => HTTP_SEE_OTHER },
        '/fourth' => { redirect => $TEST_HTTP_SERVER_URL . '/fifth', http_status_code => HTTP_TEMPORARY_REDIRECT },
        '/fifth' => 'Seems to be working.'
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/fifth', 'URL after HTTP redirects' );
    is( $response->decoded_content(), $pages->{ '/fifth' }, 'Data after HTTP redirects' );
}

sub test_get_follow_http_html_redirects_nonexistent()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # Nonexistent URL ("/first")
    my $pages = {};

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    ok( !$response->is_success );
    is_urls( $response->request()->url(), $starting_url, 'URL after unsuccessful HTTP redirects' );
}

sub test_get_follow_http_html_redirects_html()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # HTML redirects
    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
        '/second' => '<meta http-equiv="refresh" content="url=third" />',
        '/third'  => '<META HTTP-EQUIV="REFRESH" CONTENT="10; URL=/fourth" />',
        '/fourth' => '< meta content="url=fifth" http-equiv="refresh" >',
        '/fifth'  => 'Seems to be working too.'
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/fifth', 'URL after HTML redirects' );
    is( $response->decoded_content(), $pages->{ '/fifth' }, 'Data after HTML redirects' );
}

sub test_get_follow_http_html_redirects_http_loop()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # "http://127.0.0.1:9998/third?url=http%3A%2F%2F127.0.0.1%2Fsecond"
    my $third = '/third?url=' . uri_escape( $TEST_HTTP_SERVER_URL . '/second' );

    # HTTP redirects
    my $pages = {

# e.g. http://rss.nytimes.com/c/34625/f/640350/s/3a08a24a/sc/1/l/0L0Snytimes0N0C20A140C0A50C0A40Cus0Cpolitics0Cobama0Ewhite0Ehouse0Ecorrespondents0Edinner0Bhtml0Dpartner0Frss0Gemc0Frss/story01.htm
        '/first' => { redirect => '/second', http_status_code => HTTP_SEE_OTHER },

        # e.g. http://www.nytimes.com/2014/05/04/us/politics/obama-white-house-correspondents-dinner.html?partner=rss&emc=rss
        '/second' => { redirect => $third, http_status_code => HTTP_SEE_OTHER },

# e.g. http://www.nytimes.com/glogin?URI=http%3A%2F%2Fwww.nytimes.com%2F2014%2F05%2F04%2Fus%2Fpolitics%2Fobama-white-house-correspondents-dinner.html%3Fpartner%3Drss%26emc%3Drss
        '/third' => { redirect => '/second', http_status_code => HTTP_SEE_OTHER }
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/second', 'URL after HTTP redirect loop' );
}

sub test_get_follow_http_html_redirects_html_loop()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # HTML redirects
    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third" />',
        '/third'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/first', 'URL after HTML redirect loop' );
}

# Test if the subroutine acts nicely when the server decides to ensure that the
# client supports cookies (e.g.
# http://www.dailytelegraph.com.au/news/world/charlie-hebdo-attack-police-close-in-on-two-armed-massacre-suspects-as-manhunt-continues-across-france/story-fni0xs63-1227178925700)
sub test_get_follow_http_html_redirects_cookies()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';
    Readonly my $TEST_CONTENT => 'This is the content.';

    Readonly my $COOKIE_NAME    => "test_cookie";
    Readonly my $COOKIE_VALUE   => "I'm a cookie and I know it!";
    Readonly my $DEFAULT_HEADER => "Content-Type: text/html; charset=UTF-8";

    # HTTP redirects
    my $pages = {
        '/first' => {
            callback => sub {
                my ( $request ) = @_;

                my $cookies = $request->cookies();

                my $received_cookie = $cookies->{ $COOKIE_NAME };
                my $response        = '';

                if ( $received_cookie and $received_cookie eq $COOKIE_VALUE )
                {

                    TRACE "Cookie was set previously, showing page";

                    $response .= "HTTP/1.0 200 OK\r\n";
                    $response .= "$DEFAULT_HEADER\r\n";
                    $response .= "\r\n";
                    $response .= $TEST_CONTENT;

                }
                else
                {

                    TRACE "Setting cookie, redirecting to /check_cookie";

                    $response .= "HTTP/1.0 302 Moved Temporarily\r\n";
                    $response .= "$DEFAULT_HEADER\r\n";
                    $response .= "Location: /check_cookie\r\n";
                    $response .= "Set-Cookie: $COOKIE_NAME=$COOKIE_VALUE\r\n";
                    $response .= "\r\n";
                    $response .= "Redirecting to the cookie check page...";
                }

                return $response;
            }
        },

        '/check_cookie' => {
            callback => sub {

                my ( $request ) = @_;

                my $cookies = $request->cookies();

                my $received_cookie = $cookies->{ $COOKIE_NAME };
                my $response        = '';

                if ( $received_cookie and $received_cookie eq $COOKIE_VALUE )
                {

                    TRACE "Cookie was set previously, redirecting back to the initial page";

                    $response .= "HTTP/1.0 302 Moved Temporarily\r\n";
                    $response .= "$DEFAULT_HEADER\r\n";
                    $response .= "Location: $starting_url\r\n";
                    $response .= "\r\n";
                    $response .= "Cookie looks fine, redirecting you back to the article...";

                }
                else
                {

                    TRACE "Cookie wasn't found, redirecting you to the /no_cookies page...";

                    $response .= "HTTP/1.0 302 Moved Temporarily\r\n";
                    $response .= "$DEFAULT_HEADER\r\n";
                    $response .= "Location: /no_cookies\r\n";
                    $response .= "\r\n";
                    $response .= 'Cookie wasn\'t found, redirecting you to the "no cookies" page...';
                }

                return $response;
            }
        },
        '/no_cookies' => "No cookie support, go away, we don\'t like you."
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    is_urls( $response->request()->url(), $starting_url, 'URL after HTTP redirects (cookie)' );
    is( $response->decoded_content(), $TEST_CONTENT, 'Data after HTTP redirects (cookie)' );
}

sub test_get_follow_http_html_redirects_previous_responses()
{
    # HTTP redirect
    sub _page_http_redirect($)
    {
        my $page = shift;

        return {
            callback => sub {
                my ( $request ) = @_;

                my $response = '';
                $response .= "HTTP/1.0 302 Moved Temporarily\r\n";
                $response .= "Content-Type: text/plain; charset=UTF-8\r\n";
                $response .= "Location: $page\r\n";
                $response .= "\r\n";
                $response .= "Redirect to $page...";

                return $response;
            }
        };
    }

    # <meta> redirect
    sub _page_html_redirect($)
    {
        my $page = shift;

        return "<meta http-equiv='refresh' content='0; URL=$page' />";
    }

    # Various types of redirects mixed together to test setting previous()
    my $pages = {

        '/page_1' => _page_http_redirect( '/page_2' ),

        '/page_2' => _page_html_redirect( '/page_3' ),

        '/page_3' => _page_http_redirect( '/page_4' ),
        '/page_4' => _page_http_redirect( '/page_5' ),

        '/page_5' => _page_html_redirect( '/page_6' ),
        '/page_6' => _page_html_redirect( '/page_7' ),

        # Final page
        '/page_7' => 'Finally!',

    };

    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/page_1';

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    ok( $response->is_success() );
    is( $response->decoded_content(), 'Finally!' );
    is_urls( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_7" );

    # Test original_request()
    ok( $response->original_request() );
    is_urls( $response->original_request()->url(), "$TEST_HTTP_SERVER_URL/page_1" );

    # Test previous()
    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is_urls( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_6" );

    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is_urls( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_5" );

    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is_urls( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_4" );

    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is_urls( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_3" );

    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is_urls( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_2" );

    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is_urls( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_1" );

    ok( !$response->previous() );
}

sub test_parallel_get()
{
    my $pages = {

        # Test UTF-8 while we're at it
        '/a'       => '𝘛𝘩𝘪𝘴 𝘪𝘴 𝘱𝘢𝘨𝘦 𝘈.',    #
        '/b'       => '𝕿𝖍𝖎𝖘 𝖎𝖘 𝖕𝖆𝖌𝖊 𝕭.',    #
        '/c'       => '𝕋𝕙𝕚𝕤 𝕚𝕤 𝕡𝕒𝕘𝕖 ℂ.',     #
        '/timeout' => {
            callback => sub {
                my ( $request ) = @_;

                my $response = '';

                $response .= "HTTP/1.0 200 OK\r\n";
                $response .= "Content-Type: text/html; charset=UTF-8\r\n";
                $response .= "\r\n";
                $response .= "And now we wait";

                sleep( 10 );

                return $response;
            }
        },
    };

    {
        package TimeoutFasterUserAgentConfig;

        use strict;
        use warnings;

        use base 'MediaWords::Util::Config::Common::UserAgent';

        sub parallel_get_timeout()
        {
            return 2;   # time out faster
        }

        1;
    }

    my $default_ua_config = MediaWords::Util::Config::Common::user_agent();
    my $timeout_faster_ua_config = TimeoutFasterUserAgentConfig->new( $default_ua_config );
    my $ua                   = MediaWords::Util::Web::UserAgent->new( $timeout_faster_ua_config );

    my $base_url = 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $urls     = [
        "$base_url/a",
        "$base_url/b",
        "$base_url/c",
        "$base_url/timeout",                                   # times out
        "$base_url/does-not-exist",                            # does not exist
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $responses = $ua->parallel_get( $urls );

    $hs->stop();

    ok( $responses );
    ok( scalar( @{ $responses } ) == scalar( @{ $urls } ) );

    my $path_responses = {};
    foreach my $response ( @{ $responses } )
    {
        my $path = URI->new( $response->request->url )->path;
        $path_responses->{ $path } = $response;
    }

    ok( $path_responses->{ '/a' } );
    ok( $path_responses->{ '/a' }->is_success );
    is( $path_responses->{ '/a' }->decoded_content, $pages->{ '/a' } );

    ok( $path_responses->{ '/b' } );
    ok( $path_responses->{ '/b' }->is_success );
    is( $path_responses->{ '/b' }->decoded_content, $pages->{ '/b' } );

    ok( $path_responses->{ '/c' } );
    ok( $path_responses->{ '/c' }->is_success );
    is( $path_responses->{ '/c' }->decoded_content, $pages->{ '/c' } );

    ok( $path_responses->{ '/does-not-exist' } );
    ok( !$path_responses->{ '/does-not-exist' }->is_success );
    is( $path_responses->{ '/does-not-exist' }->code, 404 );

    ok( $path_responses->{ '/timeout' } );
    ok( !$path_responses->{ '/timeout' }->is_success );
    is( $path_responses->{ '/timeout' }->code, 408 );
}

sub test_determined_retries()
{
    # We'll use temporary file for inter-process communication because callback
    # will be run in a separate fork so won't be able to modify variable on
    # main process
    my ( $fh, $request_count_filename ) = tempfile();
    close( $fh );

    write_file( $request_count_filename, '0' );

    my $pages = {

        # Page that doesn't work the first two times
        '/temporarily-buggy-page' => {
            callback => sub {
                my ( $request ) = @_;

                my $response = '';

                my $temporarily_buggy_page_request_count = int( read_file( $request_count_filename ) );
                ++$temporarily_buggy_page_request_count;
                write_file( $request_count_filename, $temporarily_buggy_page_request_count );

                if ( $temporarily_buggy_page_request_count < 3 )
                {

                    say STDERR "Simulating failure for $temporarily_buggy_page_request_count time...";
                    $response .= "HTTP/1.0 500 Internal Server Error\r\n";
                    $response .= "Content-Type: text/plain\r\n";
                    $response .= "\r\n";
                    $response .= "something's wrong";

                }
                else
                {

                    say STDERR "Returning successful request...";
                    $response .= "HTTP/1.0 200 OK\r\n";
                    $response .= "Content-Type: text/plain\r\n";
                    $response .= "\r\n";
                    $response .= "success on request $temporarily_buggy_page_request_count";
                }

                return $response;

            }
        },

        # Page that doesn't work at all
        '/permanently-buggy-page' => {
            callback => sub {
                my ( $request ) = @_;

                my $response = '';
                $response .= "HTTP/1.0 500 Internal Server Error\r\n";
                $response .= "Content-Type: text/plain\r\n";
                $response .= "\r\n";
                $response .= "something's wrong";

                return $response;

            }
        },

    };
    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();

    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_timeout( 2 );    # time-out really fast

    # Try disabling retries
    $ua->set_timing( undef );
    is( $ua->timing(), undef );

    # Reenable timing
    $ua->set_timing( [ 1, 2, 4 ] );

    # For whatever reason we have to assign current timing() value to a
    # variable and only then we can cmp_deeply() it
    my $timing = $ua->timing();
    cmp_deeply( $timing, [ 1, 2, 4 ] );

    {
        my $response = $ua->get( $TEST_HTTP_SERVER_URL . '/temporarily-buggy-page' );
        ok( $response->is_success, 'Request should ultimately succeed' );
        is( $response->decoded_content, "success on request 3" );
    }

    {
        my $response = $ua->get( $TEST_HTTP_SERVER_URL . '/permanently-buggy-page' );
        ok( !$response->is_success, 'Request should fail' );
    }

    $hs->stop();
}

sub test_get_string()
{
    my $pages = { '/exists' => 'I do exist.', };
    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua = MediaWords::Util::Web::UserAgent->new();

    my $exists_string         = $ua->get_string( "$TEST_HTTP_SERVER_URL/exists" );
    my $does_not_exist_string = $ua->get_string( "$TEST_HTTP_SERVER_URL/does-not-exist" );

    $hs->stop();

    is( $exists_string,         'I do exist.' );
    is( $does_not_exist_string, undef );
}

sub test_post()
{

    sub _parse_query_string($)
    {
        my $query_string = shift;

        my $uri    = URI->new( 'http://test/?' . $query_string );
        my $params = $uri->query_form_hash();

        my $params_decoded = {};
        foreach my $key ( keys %{ $params } )
        {
            my $value = $params->{ $key };
            $params_decoded->{ decode_utf8( $key ) } = decode_utf8( $value );
        }

        return $params_decoded;
    }

    # User-Agent: and From: headers
    my $pages = {
        '/test-post' => {
            callback => sub {
                my ( $request ) = @_;

                my $response = '';

                $response .= "HTTP/1.0 200 OK\r\n";
                $response .= "Content-Type: application/json; charset=UTF-8\r\n";
                $response .= "\r\n";
                $response .= MediaWords::Util::ParseJSON::encode_json(
                    {
                        'method'       => $request->method(),
                        'content-type' => $request->content_type(),
                        'content'      => _parse_query_string( $request->content() ),
                    }
                );

                return $response;
            }
        }
    };
    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua  = MediaWords::Util::Web::UserAgent->new();
    my $url = "$TEST_HTTP_SERVER_URL/test-post";

    # UTF-8 string request
    {
        my $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $url );
        $request->set_content_type( 'application/x-www-form-urlencoded; charset=utf-8' );
        $request->set_content( 'ą=č&ė=ž' );

        my $response = $ua->request( $request );

        ok( $response->is_success() );
        is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/test-post' );

        my $decoded_json = MediaWords::Util::ParseJSON::decode_json( $response->decoded_content() );
        cmp_deeply(
            $decoded_json,
            {
                'method'       => 'POST',
                'content-type' => 'application/x-www-form-urlencoded; charset=utf-8',
                'content'      => {
                    'ą' => 'č',
                    'ė' => 'ž',
                },
            }
        );
    }

    # UTF-8 hashref request
    {
        my $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $url );
        $request->set_content_type( 'application/x-www-form-urlencoded; charset=utf-8' );
        $request->set_content(
            {
                'ą' => 'č',
                'ė' => 'ž',
            }
        );

        my $response = $ua->request( $request );

        ok( $response->is_success() );
        is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/test-post' );

        my $decoded_json = MediaWords::Util::ParseJSON::decode_json( $response->decoded_content() );
        cmp_deeply(
            $decoded_json,
            {
                'method'       => 'POST',
                'content-type' => 'application/x-www-form-urlencoded; charset=utf-8',
                'content'      => {
                    'ą' => 'č',
                    'ė' => 'ž',
                },
            }
        );
    }

    # UTF-8 encoded string request
    {
        my $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $url );
        $request->set_content_type( 'application/x-www-form-urlencoded; charset=utf-8' );
        $request->set_content( encode_utf8( 'ą=č&ė=ž' ) );

        my $response = $ua->request( $request );

        ok( $response->is_success() );
        is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/test-post' );

        my $decoded_json = MediaWords::Util::ParseJSON::decode_json( $response->decoded_content() );
        cmp_deeply(
            $decoded_json,
            {
                'method'       => 'POST',
                'content-type' => 'application/x-www-form-urlencoded; charset=utf-8',
                'content'      => {
                    'ą' => 'č',
                    'ė' => 'ž',
                },
            }
        );
    }

    # UTF-8 encoded hashref request
    {
        my $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $url );
        $request->set_content_type( 'application/x-www-form-urlencoded; charset=utf-8' );
        $request->set_content(
            {
                encode_utf8( 'ą' ) => encode_utf8( 'č' ),
                encode_utf8( 'ė' ) => encode_utf8( 'ž' ),
            }
        );

        my $response = $ua->request( $request );

        ok( $response->is_success() );
        is_urls( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/test-post' );

        my $decoded_json = MediaWords::Util::ParseJSON::decode_json( $response->decoded_content() );
        cmp_deeply(
            $decoded_json,
            {
                'method'       => 'POST',
                'content-type' => 'application/x-www-form-urlencoded; charset=utf-8',
                'content'      => {
                    'ą' => 'č',
                    'ė' => 'ž',
                },
            }
        );
    }

    $hs->stop();
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_get();
    test_get_user_agent_from_headers();
    test_get_not_found();
    test_get_valid_utf8_content();
    test_get_invalid_utf8_content();
    test_get_non_utf8_content();
    test_get_max_size();
    test_get_max_redirect();
    test_get_request_headers();
    test_get_response_status();
    test_get_response_headers();
    test_get_response_content_type();
    test_get_blacklisted_url();
    test_get_http_auth();
    test_get_authenticated_domains();

    test_get_follow_http_html_redirects_nonexistent();
    test_get_follow_http_html_redirects_http();
    test_get_follow_http_html_redirects_html();
    test_get_follow_http_html_redirects_http_loop();
    test_get_follow_http_html_redirects_html_loop();
    test_get_follow_http_html_redirects_cookies();
    test_get_follow_http_html_redirects_previous_responses();

    test_post();

    test_parallel_get();
    test_determined_retries();
    test_get_string();
}

main();
