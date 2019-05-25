use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More tests => 2;
use Test::NoWarnings;
use Test::Deep;
use Readonly;
use Data::Dumper;

use MediaWords::DB;
use MediaWords::DBI::Media::Rescrape;
use MediaWords::Test::HashServer;
use MediaWords::Test::URLs;
use MediaWords::Test::Rescrape::SampleFeed;


# Test cases when scraper always comes up with the same set of feeds
sub test_media_with_same_set_of_feeds($)
{
    my $db = shift;

    # Create test media
    Readonly my $urls_string => $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_URL;
    Readonly my $tags_string => '';
    my $medium = {
        name => 'Acme News',
        url  => $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_URL,
    };
    $medium = $db->create( 'media', $medium );
    my $media_id = $medium->{ media_id };

    # Do initial scraping for media
    my $hs = MediaWords::Test::HashServer->new(
        $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_PORT, #
        $MediaWords::Test::Rescrape::SampleFeed::PAGES_MULTIPLE,        #
    );
    $hs->start();
    MediaWords::DBI::Media::Rescrape::rescrape_media( $db, $media_id );
    $hs->stop();

    $medium = $db->find_by_id( 'media', $media_id );

    $db->query(
        <<EOF,
        INSERT INTO feeds (media_id, name, url, type, active)
            SELECT media_id, name, url, type, 't'
            FROM feeds_after_rescraping
            WHERE media_id = ?
EOF
        $media_id
    );
    $db->query(
        <<EOF,
        DELETE FROM feeds_after_rescraping
        WHERE media_id = ?
EOF
        $media_id
    );

    $medium = $db->find_by_id( 'media', $media_id );

    # Rescrape the media
    $hs = MediaWords::Test::HashServer->new(
        $MediaWords::Test::Rescrape::SampleFeed::TEST_HTTP_SERVER_PORT, #
        $MediaWords::Test::Rescrape::SampleFeed::PAGES_MULTIPLE,        #
    );
    $hs->start();
    MediaWords::DBI::Media::Rescrape::rescrape_media( $db, $media_id );
    $hs->stop();

    $medium = $db->find_by_id( 'media', $media_id );

    my $feeds_after_rescraping = $db->query( 'SELECT * FROM feeds_after_rescraping WHERE media_id = ?', $media_id )->hashes;
    is( scalar( @{ $feeds_after_rescraping } ), 0, "'feeds_after_rescraping' table must be empty after rescraping" );
}

sub main()
{
    my $db = MediaWords::DB::connect_to_db();

    test_media_with_same_set_of_feeds( $db );
}

main();
