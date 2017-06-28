use strict;
use warnings;

use Readonly;

use Test::More tests => 2;

BEGIN
{
    use_ok( 'MediaWords::Test::HTTP::HashServer' );
    use_ok( 'MediaWords::Util::Web::UserAgent' );
}

Readonly my $PORT => 8899;

# FIXME things to test:
#
# * max. download size
# * max. redirects
# * User-Agent: header
# * From: header
# * UTF-8 response
# * non-UTF-8 response
# * invalid encoding
# * timeouts
# * retries via ::Determined of specific HTTP status codes
# * retry timing via ::Determined, plus custom timing
# * custom before / after determined callbacks
# * max. redirects
# * whether or not cookies are being stored between redirects
# * blacklisted URLs
# * HTTP request log in data/logs/
# * GET
# * POST
# * request(): custom METHOD
# * request(): custom headers
# * request(): custom content type
# * request(): custom content (POST data) -- both hashref and string
# * request(): authorization
# * response: HTTP status code, message, status line
# * response: HTTP headers
# * response: content type
# * response: decoded content (UTF-8, non-UTF-8, and invalid UTF-8)
# * response: successful and unsuccessful responses
# * response: redirects and previous
# * response: get original request
# * response: errors on client/server side
# * get_string()
# * parallel_get()

sub main
{
    my $pages = {

        # Return string bigger than max. download size
        '/big_download' => {
            callback => sub {
                my ( $params, $cookies ) = @_;
                my $response = 'a' x ( 10 * 1024 * 1024 + 100 );
                return $response;
            }
        },
    };
    my $hs = MediaWords::Test::HTTP::HashServer->new( $PORT, $pages );
    $hs->start();

    $hs->stop();
}

main();
