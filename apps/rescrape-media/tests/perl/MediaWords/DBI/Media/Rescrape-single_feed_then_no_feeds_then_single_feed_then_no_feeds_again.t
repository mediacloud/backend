use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More tests => 20;
use Test::NoWarnings;
use Test::Deep;
use Readonly;
use Data::Dumper;

use MediaWords::DB;
use MediaWords::DBI::Media::Rescrape;
use MediaWords::Test::HashServer;
use MediaWords::Test::URLs;
use MediaWords::Test::Rescrape::SampleFeed;


# Media with a single feed at initial scraping and no feeds after rescraping
# (mimicking a scenario when a website is "down for maintenance" when
# rescraping)
sub test_media_single_feed_then_no_feeds_then_single_feed_then_no_feeds_again($)
{
    my $db = shift;

    # Create a test media that doesn't need rescraping
    Readonly my $urls_string => $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_URL;
    Readonly my $tags_string => '';
    my $medium = {
        name => 'Acme News',
        url  => $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_URL,
    };
    $medium = $db->create( 'media', $medium );
    my $media_id = $medium->{ media_id };

    #
    # Do initial scraping (with a single feed being present)
    #
    my $hs = MediaWords::Test::HashServer->new(
        $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_PORT, #
        $MediaWords::Test::Rescrape::SampleFeed::PAGES_SINGLE_FEED,     #
    );
    $hs->start();
    MediaWords::DBI::Media::Rescrape::rescrape_media( $db, $media_id );
    $hs->stop();

    $medium = $db->find_by_id( 'media', $media_id );

    TRACE 'Medium: ' . Dumper( $medium );

    my $feeds = $db->query( 'SELECT * FROM feeds WHERE media_id = ?', $media_id )->hashes;

    TRACE 'Feeds: ' . Dumper( $feeds );
    is( scalar( @{ $feeds } ), 1, 'Only a single feed must have been added' );
    my $rss_feed = $feeds->[ 0 ];
    is( $rss_feed->{ type }, 'syndicated', "Single feed's type must be 'syndicated'" );
    is_urls(
        $rss_feed->{ url },                                             #
        $MediaWords::Test::Rescrape::SampleFeed::PAGES_SINGLE_FEED_URL, #
        "Single feed's URL must match",                                 #
    );

    my $feeds_after_rescraping = $db->query( 'SELECT * FROM feeds_after_rescraping WHERE media_id = ?', $media_id )->hashes;

    TRACE 'Feeds after rescraping: ' . Dumper( $feeds_after_rescraping );
    is( scalar( @{ $feeds_after_rescraping } ), 0, "'feeds_after_rescraping' table must be empty after rescraping" );

    #
    # Do rescraping with no syndicated feeds being available now (for example,
    # the site is in the "maintenance mode" at the moment)
    #
    $hs = MediaWords::Test::HashServer->new(
        $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_PORT, #
        $MediaWords::Test::Rescrape::SampleFeed::PAGES_NO_FEEDS,        #
    );
    $hs->start();
    MediaWords::DBI::Media::Rescrape::rescrape_media( $db, $media_id );
    $hs->stop();

    $medium = $db->find_by_id( 'media', $media_id );

    TRACE 'Medium: ' . Dumper( $medium );

    $feeds = $db->query( 'SELECT * FROM feeds WHERE media_id = ? ORDER BY feeds_id', $media_id )->hashes;

    TRACE 'Feeds: ' . Dumper( $feeds );
    is( scalar( @{ $feeds } ),
        2, 'Two feeds must be present (one for "syndicated" feed created previously, another one ("web_page") just added)' );

    $rss_feed = $feeds->[ 0 ];
    is( $rss_feed->{ type }, 'syndicated', "First feed's type must be 'syndicated'" );
    is_urls(
        $rss_feed->{ url },                                             #
        $MediaWords::Test::Rescrape::SampleFeed::PAGES_SINGLE_FEED_URL, #
        "First feed's URL must match",                                  #
    );

    my $webpage_feed = $feeds->[ 1 ];
    is( $webpage_feed->{ type }, 'web_page', "Second feed's type must be 'web_page'" );
    is_urls(
        $webpage_feed->{ url },                                         #
        $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_URL,  #
        "Second feed's URL must be test server",                        #
    );
    ok( $webpage_feed->{ active },
        "Second feed should be active (because no syndicated feeds are available at the moment)" );

    $feeds_after_rescraping = $db->query( 'SELECT * FROM feeds_after_rescraping WHERE media_id = ?', $media_id )->hashes;

    TRACE 'Feeds after rescraping: ' . Dumper( $feeds_after_rescraping );
    is( scalar( @{ $feeds_after_rescraping } ), 0, "'feeds_after_rescraping' table must be empty after rescraping" );

    #
    # Rescrape once more, with syndicated feeds now being available once again
    #
    $hs = MediaWords::Test::HashServer->new(
        $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_PORT, #
        $MediaWords::Test::Rescrape::SampleFeed::PAGES_SINGLE_FEED,     #
    );
    $hs->start();
    MediaWords::DBI::Media::Rescrape::rescrape_media( $db, $media_id );
    $hs->stop();

    $medium = $db->find_by_id( 'media', $media_id );

    TRACE 'Medium: ' . Dumper( $medium );

    $feeds = $db->query( 'SELECT * FROM feeds WHERE media_id = ? ORDER BY feeds_id', $media_id )->hashes;

    TRACE 'Feeds: ' . Dumper( $feeds );
    is( scalar( @{ $feeds } ),
        2, 'Two feeds must be present (one for "syndicated" feed created previously, another one ("web_page") just added)' );

    $rss_feed = $feeds->[ 0 ];
    is( $rss_feed->{ type }, 'syndicated', "First feed's type must be 'syndicated'" );
    is_urls(
        $rss_feed->{ url },                                             #
        $MediaWords::Test::Rescrape::SampleFeed::PAGES_SINGLE_FEED_URL, #
        "First feed's URL must match",                                  #
    );

    $webpage_feed = $feeds->[ 1 ];
    is( $webpage_feed->{ type }, 'web_page', "Second feed's type must be 'web_page'" );
    is_urls(
        $webpage_feed->{ url },                                         #
        $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_URL,  #
        "Second feed's URL must be test server",                        #
    );
    ok( !$webpage_feed->{ active }, "Second feed should be deactivated (because now RSS feeds are alive again)" );

    $feeds_after_rescraping = $db->query( 'SELECT * FROM feeds_after_rescraping WHERE media_id = ?', $media_id )->hashes;

    TRACE 'Feeds after rescraping: ' . Dumper( $feeds_after_rescraping );
    is( scalar( @{ $feeds_after_rescraping } ), 0, "'feeds_after_rescraping' table must be empty after rescraping" );

    #
    # Rescrape one last time with no feeds, to make sure "web_page" feed doesn't get added twice
    $hs = MediaWords::Test::HashServer->new(
        $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_PORT, #
        $MediaWords::Test::Rescrape::SampleFeed::PAGES_NO_FEEDS,        #
    );
    $hs->start();
    MediaWords::DBI::Media::Rescrape::rescrape_media( $db, $media_id );
    $hs->stop();

    $medium = $db->find_by_id( 'media', $media_id );

    $feeds = $db->query( 'SELECT * FROM feeds WHERE media_id = ? ORDER BY feeds_id', $media_id )->hashes;

    TRACE 'Feeds: ' . Dumper( $feeds );
    is( scalar( @{ $feeds } ), 2, 'Two feeds must be present (like in the previous rescraping)' );
}

sub main()
{
    my $db = MediaWords::DB::connect_to_db();

    test_media_single_feed_then_no_feeds_then_single_feed_then_no_feeds_again( $db );
}

main();
