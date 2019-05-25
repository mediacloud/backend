package MediaWords::Test::Rescrape::SampleFeed;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use HTML::Entities;
use Readonly;


# must contain a hostname ('localhost') because a foreign feed link test requires it
Readonly our $TEST_HTTP_SERVER_PORT  => 9998;
Readonly our $TEST_HTTP_SERVER_URL   => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
Readonly our $TEST_HTTP_SERVER_URL_2 => 'http://127.0.0.1:' . $TEST_HTTP_SERVER_PORT;

our Readonly $HTTP_CONTENT_TYPE_RSS = 'Content-Type: application/rss+xml; charset=UTF-8';


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

Readonly our $PAGES_NO_FEEDS => {

    # Index page
    '/' => <<EOF,
        <h1>Acme News</h1>
        <p>
            Blah blah yada yada.
        </p>
        <hr />
        <p>
            This website doesn't have any RSS feeds, so it should be added
            as an "web_page" feed.
        </p>
EOF
};

Readonly our $PAGES_SINGLE_FEED_URL => $TEST_HTTP_SERVER_URL . '/feed.xml';
Readonly our $PAGES_SINGLE_FEED     => {

    # Index page
    '/' => <<"EOF",
        <html>
        <head>
            <link rel="alternate" href="$PAGES_SINGLE_FEED_URL" type="application/rss+xml" title="Acme News RSS feed" />
        </head>
        <body>
        <h1>Acme News</h1>
        <p>
            This website has a single feed that doesn't change after rescraping.
        </p>
        </body>
        </html>
EOF
    '/feed.xml' => {
        header  => $HTTP_CONTENT_TYPE_RSS,
        content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Acme News RSS feed' ),
    }
};

Readonly our $PAGES_MULTIPLE          => {

    # Index page
    '/' => <<EOF,
            <h1>Acme News</h1>
            <p>
                We didn't bother to add proper &lt;link&gt; links to our pages, but
                here's a link to the RSS link listing:<br />
                <a href="/rss">RSS</a>
            </p>
EOF

    # RSS listing page
    '/rss' => <<"EOF",
            <h1>Acme News</h1>
            <p>
            Our RSS feeds (on an external host to confuse the scraper):
            </p>
            <ul>
                <li><a href="$TEST_HTTP_SERVER_URL_2/feed1.xml">Acme News RSS feed 1</a></li>
                <li><a href="$TEST_HTTP_SERVER_URL_2/feed2.xml">Acme News RSS feed 2</a></li>
                <li><a href="$TEST_HTTP_SERVER_URL_2/feed3.xml">Acme News RSS feed 3</a></li>
                <li><a href="$TEST_HTTP_SERVER_URL_2/feed4.xml">Acme News RSS feed 4</a></li>
                <li><a href="$TEST_HTTP_SERVER_URL_2/feed5.xml">Acme News RSS feed 5</a></li>
            </ul>
EOF

    # RSS feeds on an external host
    '/feed1.xml' => {
        header  => $HTTP_CONTENT_TYPE_RSS,
        content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Acme News RSS feed 1' ),
    },
    '/feed2.xml' => {
        header  => $HTTP_CONTENT_TYPE_RSS,
        content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Acme News RSS feed 2' ),
    },
    '/feed3.xml' => {
        header  => $HTTP_CONTENT_TYPE_RSS,
        content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Acme News RSS feed 3' ),
    },
    '/feed4.xml' => {
        header  => $HTTP_CONTENT_TYPE_RSS,
        content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Acme News RSS feed 4' ),
    },
    '/feed5.xml' => {
        header  => $HTTP_CONTENT_TYPE_RSS,
        content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Acme News RSS feed 5' ),
    },
};

1;

