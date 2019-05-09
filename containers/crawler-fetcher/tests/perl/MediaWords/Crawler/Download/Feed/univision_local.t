#
# Test Univision feed implementation with local source
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::Test::Univision;
use MediaWords::DB;
use MediaWords::Util::ParseJSON;
use MediaWords::Test::HashServer;
use MediaWords::Util::Config::Crawler;

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    my $db = MediaWords::DB::connect_to_db();

    Readonly my $TEST_HTTP_SERVER_PORT => 9998;
    Readonly my $TEST_HTTP_SERVER_URL  => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

    my $local_univision_url           = $TEST_HTTP_SERVER_URL . '/feed';
    my $local_univision_client_id     = 'foo';
    my $local_univision_client_secret = 'bar';

    my $pages = {

        '/feed' => MediaWords::Util::ParseJSON::encode_json(
            {
                'status' => 'success',
                'data'   => {
                    'title'      => 'Sample Univision feed',
                    'totalItems' => 2,
                    'items'      => [
                        {
                            'type'        => 'article',
                            'uid'         => '00000156-ba02-d374-ab77-feab13e20000',
                            'url'         => $TEST_HTTP_SERVER_URL . '/first_article',
                            'publishDate' => '2016-08-23T23:32:11-04:00',
                            'updateDate'  => '2016-08-24T10:09:26-04:00',
                            'title'       => 'First article: 🍕',                           # UTF-8 in the title
                            'description' => 'This is the first Univision sample article.',
                        },
                        {
                            'type'        => 'article',
                            'uid'         => '00000156-ba73-d5b6-affe-faf77f890000',
                            'url'         => $TEST_HTTP_SERVER_URL . '/second_article',
                            'publishDate' => '2016-08-23T23:20:13-04:00',
                            'updateDate'  => '2016-08-24T09:55:40-04:00',
                            'title'       => 'Second article: 🍔',                           # UTF-8 in the title
                            'description' => 'This is the second Univision sample article.',
                        },
                    ]
                }
            }
        ),

        '/first_article' => <<EOF,
            <h1>First article</h1>
            <p>This is the first Univision sample article.</p>
EOF
        '/second_article' => <<EOF,
            <h1>Second article</h1>
            <p>This is the second Univision sample article.</p>
EOF
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    MediaWords::Test::Univision::test_univision(
        $db,                                #
        $local_univision_url,               #
        $local_univision_client_id,         #
        $local_univision_client_secret,     #
    );

    $hs->stop();

    done_testing();
}

main();
