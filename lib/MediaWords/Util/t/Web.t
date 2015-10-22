use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::Deep;
use Test::More tests => 5;

use Readonly;
use Data::Dumper;
use HTTP::HashServer;

my Readonly $TEST_HTTP_SERVER_PORT = 9998;
my Readonly $TEST_HTTP_SERVER_URL  = 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::Web' );
}

sub test_is_http_url()
{
    like(
        MediaWords::Util::Web::get_original_url_from_momento_archive_url(
            'https://web.archive.org/web/20150204024130/http://www.john-daly.com/hockey/hockey.htm'
        ),
        qr|^http://(www\.)?john\-daly\.com/hockey/hockey\.htm$|,
        'archive.org test '
    );

    like(
        MediaWords::Util::Web::get_original_url_from_momento_archive_url( 'https://archive.is/1Zcql' ),
        qr|^https?://www\.whitehouse\.gov/my2k/?$|,
        'archive.is test'
    );
}

sub test_lwp_useragent_determined_500_read_timeout()
{
    my $pages = {

        # Page that doesn't respond in time
        '/buggy-page' => {
            callback => sub {
                my ( $self, $cgi ) = @_;
                print "HTTP/1.0 200 OK\r\n";
                print "Content-Type: text/plain\r\n";
                print "\r\n";

                # Simulate read timeout
                sleep;
            }
        }
    };
    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();

    my $ua = MediaWords::Util::Web::UserAgentDetermined();
    $ua->timeout( 5 );    # time-out really fast
    $ua->timing( '1,2,4' );

    my $response = $ua->get( $TEST_HTTP_SERVER_URL . '/buggy-page' );
    ok( !$response->is_success, 'Request should fail' );
    $response->decoded_content();

    $hs->stop();
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_is_http_url();
    test_lwp_useragent_determined_500_read_timeout();
}

main();
