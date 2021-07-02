use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::DB;
use MediaWords::Test::API;
use MediaWords::Test::Rows;
use MediaWords::Test::DB::Create;
use MediaWords::Test::Solr;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

# test feeds/list and single
sub test_feeds_list($)
{
    my ( $db ) = @_;

    my $label = "feeds/list";

    my $medium = MediaWords::Test::DB::Create::create_test_medium( $db, $label );

    map { MediaWords::Test::DB::Create::create_test_feed( $db, "$label $_", $medium ) } ( 1 .. 10 );

    my $expected_feeds = $db->query( "SELECT * FROM feeds WHERE media_id = ?", $medium->{ media_id } )->hashes;

    my $got_feeds = MediaWords::Test::API::test_get( '/api/v2/feeds/list', { media_id => $medium->{ media_id } } );

    my $fields = [ qw ( name url media_id feeds_id type active ) ];
    MediaWords::Test::Rows::rows_match( $label, $got_feeds, $expected_feeds, "feeds_id", $fields );

    $label = "feeds/single";

    my $expected_single = $expected_feeds->[ 0 ];

    my $got_feed = MediaWords::Test::API::test_get( '/api/v2/feeds/single/' . $expected_single->{ feeds_id }, {} );
    MediaWords::Test::Rows::rows_match( $label, $got_feed, [ $expected_single ], 'feeds_id', $fields );
}

sub test_feeds($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack_numerated(
        $db,
        $NUM_MEDIA,
        $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED
    );

    $media = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $db, $media );

    # MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    # test for required fields errors
    MediaWords::Test::API::test_post( '/api/v2/feeds/create', {}, 1 );
    MediaWords::Test::API::test_put( '/api/v2/feeds/update', { name => 'foo' }, 1 );

    my $medium = $db->query( "select * from media limit 1" )->hash;

    # simple tag creation
    my $create_input = {
        media_id => $medium->{ media_id },
        name     => 'feed name',
        url      => 'http://feed.create',
        type     => 'syndicated',
        active   => 't',
    };

    my $r = MediaWords::Test::API::test_post( '/api/v2/feeds/create', $create_input );
    MediaWords::Test::Rows::validate_db_row( $db, 'feeds', $r->{ feed }, $create_input, 'create feed' );

    # error on update non-existent tag
    MediaWords::Test::API::test_put( '/api/v2/feeds/update', { feeds_id => -1 }, 1 );

    # simple update
    my $update_input = {
        feeds_id => $r->{ feed }->{ feeds_id },
        name     => 'feed name update',
        url      => 'http://feed.create/update',
        type     => 'web_page',
        active   => 'f',
    };

    $r = MediaWords::Test::API::test_put( '/api/v2/feeds/update', $update_input );
    MediaWords::Test::Rows::validate_db_row( $db, 'feeds', $r->{ feed }, $update_input, 'update feed' );

    $r = MediaWords::Test::API::test_post( '/api/v2/feeds/scrape', { media_id => $medium->{ media_id } } );
    ok( $r->{ job_state }, "feeds/scrape job state returned" );
    is( $r->{ job_state }->{ media_id }, $medium->{ media_id }, "feeds/scrape media_id" );
    ok( $r->{ job_state }->{ state } ne 'error', "feeds/scrape job state is not an error" );

    $r = MediaWords::Test::API::test_get( '/api/v2/feeds/scrape_status', { media_id => $medium->{ media_id } } );
    is( $r->{ job_states }->[ 0 ]->{ media_id }, $medium->{ media_id }, "feeds/scrape_status media_id" );

    $r = MediaWords::Test::API::test_get( '/api/v2/feeds/scrape_status', {} );
    is( $r->{ job_states }->[ 0 ]->{ media_id }, $medium->{ media_id }, "feeds/scrape_status all media_id" );

    test_feeds_list( $db );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_feeds( $db );

    done_testing();
}

main();
