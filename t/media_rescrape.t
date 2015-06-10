use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More tests => 12;
use Test::NoWarnings;
use Test::Deep;

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::Test::DB;
use MediaWords::DBI::Media;

use HTTP::HashServer;
use Readonly;
use Data::Dumper;

# must contain a hostname ('localhost') because a foreign feed link test requires it
Readonly my $TEST_HTTP_SERVER_PORT => 9998;
Readonly my $TEST_HTTP_SERVER_URL  => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

Readonly my $HTTP_CONTENT_TYPE_RSS => 'Content-Type: application/rss+xml; charset=UTF-8';

# Media without any feeds
sub test_media_no_feeds($)
{
    my $db = shift;

    my $pages = {

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
    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    # Create a test media that doesn't need rescraping
    Readonly my $urls_string => $TEST_HTTP_SERVER_URL;
    Readonly my $tags_string => '';
    my $medium = {
        name      => 'Acme News',
        url       => $TEST_HTTP_SERVER_URL,
        moderated => 'f',
    };
    $medium = $db->create( 'media', $medium );
    my $media_id = $medium->{ media_id };

    # Test the whole process two times to simulate initial scraping and rescraping
    for ( my $x = 0 ; $x < 2 ; ++$x )
    {

        MediaWords::DBI::Media::Rescrape::rescrape_media( $db, $media_id );

        $medium = $db->find_by_id( 'media', $media_id );

        # say STDERR 'Medium: ' . Dumper( $medium );
        ok( $medium->{ moderated }, 'Media must be moderated after rescraping' );

        my $feeds = $db->query( 'SELECT * FROM feeds WHERE media_id = ?', $media_id )->hashes;

        # say STDERR 'Feeds: ' . Dumper( $feeds );
        ok( scalar( @{ $feeds } ), 'Only a single feed must have been added' );
        my $webpage_feed = $feeds->[ 0 ];
        is( $webpage_feed->{ feed_type }, 'web_page',            "Single feed's type must be 'web_page'" );
        is( $webpage_feed->{ url },       $TEST_HTTP_SERVER_URL, "Single feed's URL must be test server" );

        my $feeds_after_rescraping =
          $db->query( 'SELECT * FROM feeds_after_rescraping WHERE media_id = ?', $media_id )->hashes;

        # say STDERR 'Feeds after rescraping: ' . Dumper( $feeds_after_rescraping );
        ok( scalar( @{ $feeds_after_rescraping } ) == 0, "'feeds_after_rescraping' table must be empty after rescraping" );

    }

    $hs->stop();
}

sub main()
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;

            test_media_no_feeds( $db );

            Test::NoWarnings::had_no_warnings();
        }
    );
}

main();
