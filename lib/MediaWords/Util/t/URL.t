use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::NoWarnings;
use Test::Deep;
use Test::More tests => 27;

use Readonly;
use HTTP::HashServer;
use HTTP::Status qw(:constants);
use URI::Escape;
use Data::Dumper;

use MediaWords::Test::DB;

Readonly my $TEST_HTTP_SERVER_PORT => 9998;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::URL' );
}

sub test_url_and_data_after_redirects_http()
{
    eval { MediaWords::Util::URL::url_and_data_after_redirects( undef ); };
    ok( $@, 'Undefined URL' );

    eval { MediaWords::Util::URL::url_and_data_after_redirects( 'gopher://gopher.floodgap.com/0/v2/vstat' ); };
    ok( $@, 'Non-HTTP(S) URL' );

    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # HTTP redirects
    my $pages = {
        '/first'  => { redirect => '/second',                        http_status_code => HTTP_MOVED_PERMANENTLY },
        '/second' => { redirect => $TEST_HTTP_SERVER_URL . '/third', http_status_code => HTTP_FOUND },
        '/third'  => { redirect => '/fourth',                        http_status_code => HTTP_SEE_OTHER },
        '/fourth' => { redirect => $TEST_HTTP_SERVER_URL . '/fifth', http_status_code => HTTP_TEMPORARY_REDIRECT },
        '/fifth' => 'Seems to be working.'
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects,  $TEST_HTTP_SERVER_URL . '/fifth', 'URL after HTTP redirects' );
    is( $data_after_redirects, $pages->{ '/fifth' },             'Data after HTTP redirects' );
}

sub test_url_and_data_after_redirects_nonexistent()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # Nonexistent URL ("/first")
    my $pages = {};

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects,  $starting_url, 'URL after unsuccessful HTTP redirects' );
    is( $data_after_redirects, undef,         'Data after unsuccessful HTTP redirects' );
}

sub test_url_and_data_after_redirects_html()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';
    Readonly my $MAX_META_REDIRECTS => 7;    # instead of default 3

    # HTML redirects
    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
        '/second' => '<meta http-equiv="refresh" content="url=third" />',
        '/third'  => '<META HTTP-EQUIV="REFRESH" CONTENT="10; URL=/fourth" />',
        '/fourth' => '< meta content="url=fifth" http-equiv="refresh" >',
        '/fifth'  => 'Seems to be working too.'
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url, undef, $MAX_META_REDIRECTS );

    $hs->stop();

    is( $url_after_redirects,  $TEST_HTTP_SERVER_URL . '/fifth', 'URL after HTML redirects' );
    is( $data_after_redirects, $pages->{ '/fifth' },             'Data after HTML redirects' );
}

sub test_url_and_data_after_redirects_http_loop()
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

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects, $TEST_HTTP_SERVER_URL . '/second', 'URL after HTTP redirect loop' );
}

sub test_url_and_data_after_redirects_html_loop()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # HTML redirects
    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third" />',
        '/third'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects, $TEST_HTTP_SERVER_URL . '/second', 'URL after HTML redirect loop' );
}

# Test if the subroutine acts nicely when the server decides to ensure that the
# client supports cookies (e.g.
# http://www.dailytelegraph.com.au/news/world/charlie-hebdo-attack-police-close-in-on-two-armed-massacre-suspects-as-manhunt-continues-across-france/story-fni0xs63-1227178925700)
sub test_url_and_data_after_redirects_cookies()
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
                my ( $self, $cgi ) = @_;

                my $received_cookie = $cgi->cookie( $COOKIE_NAME );

                if ( $received_cookie and $received_cookie eq $COOKIE_VALUE )
                {

                    TRACE "Cookie was set previously, showing page";

                    print "HTTP/1.0 200 OK\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "\r\n";
                    print $TEST_CONTENT;

                }
                else
                {

                    TRACE "Setting cookie, redirecting to /check_cookie";

                    print "HTTP/1.0 302 Moved Temporarily\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "Location: /check_cookie\r\n";
                    print "Set-Cookie: $COOKIE_NAME=$COOKIE_VALUE\r\n";
                    print "\r\n";
                    print "Redirecting to the cookie check page...";
                }
            }
        },

        '/check_cookie' => {
            callback => sub {

                my ( $self, $cgi ) = @_;

                my $received_cookie = $cgi->cookie( $COOKIE_NAME );

                if ( $received_cookie and $received_cookie eq $COOKIE_VALUE )
                {

                    TRACE "Cookie was set previously, redirecting back to the initial page";

                    print "HTTP/1.0 302 Moved Temporarily\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "Location: $starting_url\r\n";
                    print "\r\n";
                    print "Cookie looks fine, redirecting you back to the article...";

                }
                else
                {

                    TRACE "Cookie wasn't found, redirecting you to the /no_cookies page...";

                    print "HTTP/1.0 302 Moved Temporarily\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "Location: /no_cookies\r\n";
                    print "\r\n";
                    print 'Cookie wasn\'t found, redirecting you to the "no cookies" page...';
                }
            }
        },
        '/no_cookies' => "No cookie support, go away, we don\'t like you."
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects,  $starting_url, 'URL after HTTP redirects (cookie)' );
    is( $data_after_redirects, $TEST_CONTENT, 'Data after HTTP redirects (cookie)' );
}

sub test_all_url_variants($)
{
    my ( $db ) = @_;

    my @actual_url_variants;
    my @expected_url_variants;

    # Undefined URL
    eval { MediaWords::Util::URL::all_url_variants( $db, undef ); };
    ok( $@, 'Undefined URL' );

    # Non-HTTP(S) URL
    Readonly my $gopher_url => 'gopher://gopher.floodgap.com/0/v2/vstat';
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $gopher_url );
    @expected_url_variants = ( $gopher_url );
    is_deeply( [ sort @actual_url_variants ], [ sort @expected_url_variants ], 'Non-HTTP(S) URL' );

    # Basic test
    Readonly my $TEST_HTTP_SERVER_URL       => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    Readonly my $starting_url_without_cruft => $TEST_HTTP_SERVER_URL . '/first';
    Readonly my $cruft                      => '?utm_source=A&utm_medium=B&utm_campaign=C';
    Readonly my $starting_url               => $starting_url_without_cruft . $cruft;

    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third' . $cruft . '" />',
        '/third'  => 'This is where the redirect chain should end.',
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url, $starting_url_without_cruft,
        $TEST_HTTP_SERVER_URL . '/third',
        $TEST_HTTP_SERVER_URL . '/third' . $cruft
    );
    is_deeply( [ sort @actual_url_variants ], [ sort @expected_url_variants ], 'Basic all_url_variants() test' );

    # <link rel="canonical" />
    $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third' . $cruft . '" />',
        '/third'  => '<link rel="canonical" href="' . $TEST_HTTP_SERVER_URL . '/fourth" />',
    };

    $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url, $starting_url_without_cruft,
        $TEST_HTTP_SERVER_URL . '/third',
        $TEST_HTTP_SERVER_URL . '/third' . $cruft,
        $TEST_HTTP_SERVER_URL . '/fourth',
    );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        '<link rel="canonical" /> all_url_variants() test'
    );

    # Redirect to a homepage
    $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/',
    };

    $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url_without_cruft, $starting_url,
        $TEST_HTTP_SERVER_URL . '/second',
        $TEST_HTTP_SERVER_URL . '/second' . $cruft
    );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        '"Redirect to homepage" all_url_variants() test'
    );
}

sub test_all_url_variants_invalid_variants($)
{
    my ( $db ) = @_;

    my @actual_url_variants;
    my @expected_url_variants;

    # Invalid URL variant (suspended Twitter account)
    Readonly my $invalid_url_variant => 'https://twitter.com/Todd__Kincannon/status/518499096974614529';
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $invalid_url_variant );
    @expected_url_variants = ( $invalid_url_variant );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        'Invalid URL variant (suspended Twitter account)'
    );
}

sub test_get_topic_url_variants
{
    my ( $db ) = @_;

    my $data = {
        A => {
            B => [ 1, 2, 3 ],
            C => [ 4, 5, 6 ]
        },
        D => { E => [ 7, 8, 9 ] }
    };

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, $data );

    my $story_1 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 1 };
    my $story_2 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 2 };
    my $story_3 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 3 };
    my $story_4 = $media->{ A }->{ feeds }->{ C }->{ stories }->{ 4 };

    $db->query( <<END, $story_2->{ stories_id }, $story_1->{ stories_id } );
insert into topic_merged_stories_map ( source_stories_id, target_stories_id ) values( ?, ? )
END
    $db->query( <<END, $story_3->{ stories_id }, $story_2->{ stories_id } );
insert into topic_merged_stories_map ( source_stories_id, target_stories_id ) values( ?, ? )
END

    my $tag_set = $db->create( 'tag_sets', { name => 'foo' } );

    my $topic = {
        name            => 'foo',
        pattern         => 'foo',
        solr_seed_query => 'foo',
        description     => 'foo',
    };
    $topic = $db->create( 'topics', $topic );

    $db->create(
        'topic_stories',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_4->{ stories_id }
        }
    );

    $db->create(
        'topic_stories',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_1->{ stories_id }
        }
    );

    $db->create(
        'topic_links',
        {
            topics_id      => $topic->{ topics_id },
            stories_id     => $story_4->{ stories_id },
            ref_stories_id => $story_1->{ stories_id },
            url            => $story_1->{ url },
            redirect_url   => $story_1->{ url } . "/redirect_url"
        }
    );

    $db->create(
        'topic_stories',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_2->{ stories_id }
        }
    );

    $db->create(
        'topic_links',
        {
            topics_id      => $topic->{ topics_id },
            stories_id     => $story_4->{ stories_id },
            ref_stories_id => $story_2->{ stories_id },
            url            => $story_2->{ url },
            redirect_url   => $story_2->{ url } . "/redirect_url"
        }
    );

    $db->create(
        'topic_stories',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_3->{ stories_id }
        }
    );

    $db->create(
        'topic_links',
        {
            topics_id      => $topic->{ topics_id },
            stories_id     => $story_4->{ stories_id },
            ref_stories_id => $story_3->{ stories_id },
            url            => $story_3->{ url } . '/alternate',
        }
    );

    my $expected_urls = [
        $story_1->{ url },
        $story_2->{ url },
        $story_1->{ url } . "/redirect_url",
        $story_2->{ url } . "/redirect_url",
        $story_3->{ url },
        $story_3->{ url } . "/alternate"
    ];

    my @test_urls = ( $story_1->{ url } );
    my $url_variants = MediaWords::Util::URL::get_topic_url_variants( $db, \@test_urls );

    $url_variants  = [ sort { $a cmp $b } @{ $url_variants } ];
    $expected_urls = [ sort { $a cmp $b } @{ $expected_urls } ];

    is( scalar( @{ $url_variants } ), scalar( @{ $expected_urls } ), 'test_get_topic_url_variants: same number variants' );

    for ( my $i = 0 ; $i < @{ $expected_urls } ; $i++ )
    {
        is( $url_variants->[ $i ], $expected_urls->[ $i ], 'test_get_topic_url_variants: url variant match $i' );
    }
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_url_and_data_after_redirects_nonexistent();
    test_url_and_data_after_redirects_http();
    test_url_and_data_after_redirects_html();
    test_url_and_data_after_redirects_http_loop();
    test_url_and_data_after_redirects_html_loop();
    test_url_and_data_after_redirects_cookies();

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_all_url_variants( $db );
        }
    );

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_all_url_variants_invalid_variants( $db );
        }
    );

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_get_topic_url_variants( $db );
        }
    );

}

main();
