use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::NoWarnings;
use Test::Deep;
use Test::More tests => 5;

use Readonly;
use Data::Dumper;
use MediaWords::Test::HTTP::HashServer;
use URI;

use MediaWords::Util::Web;

my Readonly $TEST_HTTP_SERVER_PORT = 9998;
my Readonly $TEST_HTTP_SERVER_URL  = 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

sub test_parallel_get()
{
    my $pages = {

        # Test UTF-8 while we're at it
        '/a' => '𝘛𝘩𝘪𝘴 𝘪𝘴 𝘱𝘢𝘨𝘦 𝘈.',    #
        '/b' => '𝕿𝖍𝖎𝖘 𝖎𝖘 𝖕𝖆𝖌𝖊 𝕭.',    #
        '/c' => '𝕋𝕙𝕚𝕤 𝕚𝕤 𝕡𝕒𝕘𝕖 ℂ.',     #
    };
    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $urls = [];
    foreach my $path ( keys %{ $pages } )
    {
        push( @{ $urls }, 'http://localhost:' . $TEST_HTTP_SERVER_PORT . $path );
    }

    my $ua        = MediaWords::Util::Web::UserAgent->new();
    my $responses = $ua->parallel_get( $urls );

    ok( $responses );
    ok( scalar( @{ $responses } ) == scalar( @{ $urls } ) );

    my $paths_and_contents = {};
    foreach my $response ( @{ $responses } )
    {
        my $path    = URI->new( $response->request->url )->path;
        my $content = $response->decoded_content;
        $paths_and_contents->{ $path } = $content;
    }

    cmp_deeply( $paths_and_contents, $pages );

    $hs->stop();
}

sub test_lwp_user_agent_retries()
{
    my $pages = {

        # Page that doesn't respond in time
        '/buggy-page' => {
            callback => sub {
                my ( $params, $cookies ) = @_;

                # Simulate read timeout
                sleep;
            }
        }
    };
    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

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

    test_parallel_get();
    test_lwp_user_agent_retries();
}

main();
