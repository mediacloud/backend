use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::Deep;
use Test::More tests => 3;

use Readonly;
use Data::Dumper;
use HTTP::HashServer;
use HTTP::Response;

use MediaWords::Util::Web;

my Readonly $TEST_HTTP_SERVER_PORT = 9998;
my Readonly $TEST_HTTP_SERVER_URL  = 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::Web' );
}

sub test_lwp_user_agent_retries()
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

    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_timeout( 2 );    # time-out really fast
    $ua->set_timing( '1,2,4' );

    my $response = $ua->get( $TEST_HTTP_SERVER_URL . '/buggy-page' );
    ok( !$response->is_success, 'Request should fail' );
    $response->decoded_content;

    $hs->stop();
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_lwp_user_agent_retries();
}

main();
