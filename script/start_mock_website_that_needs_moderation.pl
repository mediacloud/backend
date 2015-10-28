#!/usr/bin/env perl

#
# Starts a mock website that always needs moderation when being scraped for feeds
#
# Usage:
#
# 1) ./script/run_with_carton ./script/start_mock_website_that_needs_moderation.pl [ http_port ]
# 2) Go to http://127.0.0.1:3000/admin/media/create_batch, add the URL of the mock HTTP server to the list of media items
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use HTTP::HashServer;
use HTML::Entities;
use Encode;

my Readonly $HTTP_CONTENT_TYPE_RSS = 'Content-Type: application/rss+xml; charset=UTF-8';

sub _sample_rss_feed($;$)
{
    my ( $base_url, $title ) = @_;

    $title ||= 'Sample RSS feed';

    $base_url = encode_entities( $base_url, '<>&' );
    $title    = encode_entities( $title,    '<>&' );

    return <<"EOF";
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
    <channel>
        <title>$title</title>
        <link>$base_url</link>
        <description>This is a sample RSS feed.</description>
        <item>
            <title>First post</title>
            <link>$base_url/first</link>
            <description>Here goes the first post in a sample RSS feed.</description>
        </item>
        <item>
            <title>Second post</title>
            <link>$base_url/second</link>
            <description>Here goes the second post in a sample RSS feed.</description>
        </item>
    </channel>
</rss>
EOF
}

sub main()
{
    my Readonly $test_http_server_port = 10000;
    if ( $ARGV[ 0 ] )
    {
        $test_http_server_port = $ARGV[ 0 ] + 0;
    }
    my Readonly $test_http_server_url = 'http://localhost:' . $test_http_server_port;

    # Use IP instead of host so that Feed::Scrape thinks that feeds are on a different host
    my Readonly $test_http_server_url_2 = 'http://127.0.0.1:' . $test_http_server_port;

    my $pages = {

        # Index page
        '/' => <<EOF,
            <h1>Acme News</h1>
            <p>
                We didn't bother to add proper &lt;link&gt; links to our pages, but
                here's a link to the RSS link listing:<br />
                <a href="/rss">RSS</a>
            </p>
EOF

        # URL that looks like a feed but doesn't contain one
        '/feed' => <<EOF,
            The feed searcher will look here, but there is no feed to be found at this URL.
EOF

        # RSS listing page
        '/rss' => <<"EOF",
            <h1>Acme News</h1>
            <p>
            Our RSS feeds:
            </p>
            <ul>
                <li><a href="$test_http_server_url_2/syndicated/all.xml">All News</a></li>
                <li><a href="$test_http_server_url_2/syndicated/politics.xml">Politics</a></li>
                <li><a href="$test_http_server_url_2/syndicated/sports.xml">Sports</a></li>
                <li><a href="$test_http_server_url_2/syndicated/technology.xml">Technology</a></li>
                <li><a href="$test_http_server_url_2/syndicated/kardashians.xml">Kardashians</a></li>
            </ul>
EOF

        # RSS feeds (the total count exceeding $Feed::Scrape::MAX_DEFAULT_FEEDS)
        '/syndicated/all.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $test_http_server_url, 'All News' )
        },
        '/syndicated/politics.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $test_http_server_url, 'Politics' )
        },
        '/syndicated/sports.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $test_http_server_url, 'Sports' )
        },
        '/syndicated/technology.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $test_http_server_url, 'Technology' )
        },
        '/syndicated/kardashians.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $test_http_server_url, 'Kardashians' )
        },
    };

    my $hs = HTTP::HashServer->new( $test_http_server_port, $pages );
    $hs->start();
    sleep;
}

main();
