use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More tests => 21;
use Test::NoWarnings;
use Test::Deep;
use Readonly;
use Data::Dumper;

use MediaWords::DB;
use MediaWords::DBI::Media::Rescrape;
use MediaWords::Test::HashServer;
use MediaWords::Test::URLs;
use MediaWords::Test::Rescrape::SampleFeed;


# Media with a single feed that doesn't change when rescraping
sub test_media_single_feed($)
{
    my $db = shift;

    my $hs = MediaWords::Test::HashServer->new(
        $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_PORT, #
        $MediaWords::Test::Rescrape::SampleFeed::PAGES_SINGLE_FEED,     #
    );
    $hs->start();

    # Create a test media that doesn't need rescraping
    Readonly my $urls_string => $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_URL;
    Readonly my $tags_string => '';
    my $medium = {
        name => 'Acme News',
        url  => $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_URL,
    };
    $medium = $db->create( 'media', $medium );
    my $media_id = $medium->{ media_id };

    # Test the whole process multiple times to simulate initial scraping and rescraping
    for ( my $x = 0 ; $x < 5 ; ++$x )
    {
        MediaWords::DBI::Media::Rescrape::rescrape_media( $db, $media_id );

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

        my $feeds_after_rescraping =
          $db->query( 'SELECT * FROM feeds_after_rescraping WHERE media_id = ?', $media_id )->hashes;

        TRACE 'Feeds after rescraping: ' . Dumper( $feeds_after_rescraping );
        is( scalar( @{ $feeds_after_rescraping } ), 0, "'feeds_after_rescraping' table must be empty after rescraping" );
    }

    $hs->stop();
}

sub main()
{
    my $db = MediaWords::DB::connect_to_db();

    test_media_single_feed( $db );
}

main();
