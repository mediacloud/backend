#!/usr/bin/env perl

# general test of api end popints

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";

}

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Catalyst::Test 'MediaWords';
use HTTP::HashServer;
use HTTP::Request;
use Readonly;
use Test::More;
use URI::Escape;

use MediaWords::Test::DB;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;
use MediaWords::Util::Web;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

my $_api_token;

#  test that we got a valid response,
# that the response is valid json, and that the json response is not an error response.  Return
# the decoded json.  If $expect_error is true, test for expected error response.
sub test_request_response($$;$)
{
    my ( $label, $response, $expect_error ) = @_;

    my $url = $response->request->url;

    is( $response->is_success, !$expect_error, "HTTP response status OK for $label" );

    my $data = MediaWords::Util::JSON::decode_json( $response->content );

    ok( $data, "decoded json for $label" );

    if ( $expect_error )
    {
        ok( ( ( ref( $data ) eq ref( {} ) ) && $data->{ error } ), "response is an error for $label" );
    }
    else
    {
        ok( !( ( ref( $data ) eq ref( {} ) ) && $data->{ error } ), "response is not an error for $label" );
    }

    return $data;
}

# execute Catalyst::Test::request with an HTTP request with the given data as json content.
# call test_request_response() on the result and return the decoded json data
sub test_data_request($$$;$)
{
    my ( $method, $url, $data, $expect_error ) = @_;

    $url = "$url?key=$_api_token";

    my $json = MediaWords::Util::JSON::encode_json( $data );

    my $request = HTTP::Request->new( $method, $url );
    $request->header( 'Content-Type' => 'application/json' );
    $request->content( $json );

    my $label = $request->as_string;

    return test_request_response( $label, request( $request ), $expect_error );
}

# call test_data_request with a 'PUT' method
sub test_put($$;$)
{
    my ( $url, $data, $expect_error ) = @_;

    return test_data_request( 'PUT', $url, $data, $expect_error );
}

# call test_data_request with a 'POST' method
sub test_post($$;$)
{
    my ( $url, $data, $expect_error ) = @_;

    return test_data_request( 'POST', $url, $data, $expect_error );
}

# execute Catalyst::Test::request on the given url with the given params and then call test_request_response()
# to test and return the decode json data
sub test_get($;$$)
{
    my ( $url, $params, $expect_error ) = @_;

    $params //= {};
    $params->{ key } //= $_api_token;

    my $encoded_params = join( "&", map { $_ . '=' . uri_escape( $params->{ $_ } ) } keys( %{ $params } ) );

    my $full_url = "$url?$encoded_params";

    return test_request_response( $full_url, request( $full_url ), $expect_error );
}

# test that a story has the expected content
sub test_story_fields($$)
{
    my ( $story, $test ) = @_;

    my ( $num ) = ( $story->{ title } =~ /story story_(\d+)/ );

    ok( defined( $num ), "$test: found story number from title: $story->{ title }" );

    is( $story->{ url },           "http://story.test/story_$num", "$test: story url" );
    is( $story->{ guid },          "guid://story.test/story_$num", "$test: story guid" );
    is( $story->{ language },      "en",                           "$test: story language" );
    is( $story->{ ap_syndicated }, 0,                              "$test: story ap_syndicated" );

}

# various tests to validate stories_public/list
sub test_stories_public_list($$)
{
    my ( $db, $test_media ) = @_;

    my $stories = test_get( '/api/v2/stories_public/list', { q => 'title:story*', rows => 100000 } );

    my $expected_num_stories = $NUM_MEDIA * $NUM_FEEDS_PER_MEDIUM * $NUM_STORIES_PER_FEED;
    my $got_num_stories      = scalar( @{ $stories } );
    is( $got_num_stories, $expected_num_stories, "stories_public/list: number of stories" );

    my $title_stories_lookup = {};
    my $expected_stories = [ grep { $_->{ stories_id } } values( %{ $test_media } ) ];
    map { $title_stories_lookup->{ $_->{ title } } = $_ } @{ $expected_stories };

    for my $i ( 0 .. $expected_num_stories - 1 )
    {
        my $expected_title = "story story_$i";
        my $found_story    = $title_stories_lookup->{ $expected_title };
        ok( $found_story, "found story with title '$expected_title'" );
        test_story_fields( $stories->[ $i ], "all stories: story $i" );
    }

    my $search_result =
      test_get( '/api/v2/stories_public/list', { q => 'stories_id:' . $stories->[ 0 ]->{ stories_id } } );
    is( scalar( @{ $search_result } ), 1, "stories_public search: count" );
    is( $search_result->[ 0 ]->{ stories_id }, $stories->[ 0 ]->{ stories_id }, "stories_public search: stories_id match" );
    test_story_fields( $search_result->[ 0 ], "story_public search" );

    my $stories_single = test_get( '/api/v2/stories_public/single/' . $stories->[ 1 ]->{ stories_id } );
    is( scalar( @{ $stories_single } ), 1, "stories_public/single: count" );
    is( $stories_single->[ 0 ]->{ stories_id }, $stories->[ 1 ]->{ stories_id }, "stories_public/single: stories_id match" );
    test_story_fields( $search_result->[ 0 ], "stories_public/single" );
}

# test auth/profile call
sub test_auth_profile($)
{
    my ( $db ) = @_;

    my $expected_user = $db->query( <<SQL, $_api_token )->hash;
select * from auth_users au join auth_user_limits using ( auth_users_id ) where api_token = \$1
SQL
    my $profile = test_get( "/api/v2/auth/profile" );

    for my $field ( qw/email auth_users_id weekly_request_items_limit non_public_api notes active weekly_requests_limit/ )
    {
        is( $profile->{ $field }, $expected_user->{ $field }, "auth profile $field" );
    }
}

# test that the values at the given fields are equal in each hash, using the given test label
sub _compare_fields($$$$)
{
    my ( $label, $got, $expected, $fields ) = @_;

    for my $field ( @{ $fields } )
    {
        is( $got->{ $field }, $expected->{ $field }, "$label $field" );
    }
}

# wait for feed scraping to happen and verify that a valid feed has been discovered for each site
sub test_for_scraped_feeds($$)
{
    my ( $db, $sites ) = @_;

    my $timeout = 90;
    my $i       = 0;
    while ( $i++ < $timeout )
    {
        my ( $num_waiting_media ) =
          $db->query( "select count(*) from media_rescraping where last_rescrape_time is null" )->flat;
        ( $num_waiting_media > 0 ) ? sleep 1 : last;
        DEBUG( "wait for feed scraping ($num_waiting_media) ..." );
    }

    ok( 0, "timed out waiting for scraped feeds" ) if ( $i == $timeout );

    for my $site ( @{ $sites } )
    {
        my $medium = $db->query( "select * from media where name = ?", $site->{ name } )->hash
          || die( "unable to find medium for site $site->{ name }" );
        my $feed = $db->query( "select * from feeds where media_id = ?", $medium->{ media_id } )->hash;
        ok( $feed, "feed exists for site $site->{ name } media_id $medium->{ media_id }" );
        is( $feed->{ feed_type },   'syndicated',        "$site->{ name } feed type" );
        is( $feed->{ feed_status }, 'active',            "$site->{ name } feed status" );
        is( $feed->{ url },         $site->{ feed_url }, "$site->{ name } feed url" );
    }
}

# start a HTTP::HashServer with the following pages for each of the given site names:
# * home page - http://localhost:$port/$site
# * feed page - http://localhost:$port/$site/feed
# * custom feed page - http://localhost:$port/$site/custom_feed
#
# return the HTTP::HashServer
sub start_media_create_hash_server
{
    my ( $site_names ) = @_;

    my $port = 8976;

    my $pages = {};
    for my $site_name ( @{ $site_names } )
    {
        $pages->{ "/$site_name" } = "<html><title>$site_name</title><body>$site_name body</body>";

        my $atom = <<ATOM;
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
	<title>$site_name</title>
	<link href="http://localhost:$port/$site_name" />
	<id>urn:uuid:60a76c80-d399-11d9-b91C-0003939e0af6</id>
	<updated>2015-12-13T18:30:02Z</updated>
	<entry>
		<title>$site_name page</title>
		<link href="http://localhost:$port/$site_name/page" />
		<id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>
		<updated>2015-12-13T18:30:02Z</updated>
	</entry>
</feed>
ATOM

        $pages->{ "/$site_name/feed" }        = { header => 'Content-Type: application/atom+xml', content => $atom };
        $pages->{ "/$site_name/custom_feed" } = { header => 'Content-Type: application/atom+xml', content => $atom };
    }

    my $hs = HTTP::HashServer->new( $port, $pages );

    $hs->start();

    return $hs;
}

# test that the feeds and tags_ids fields update existing media sources when passed to create
sub test_media_create_update($$)
{
    my ( $db, $sites ) = @_;

    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'media_test:media_test' );

    my $input = [
        map {
            {
                url      => $_->{ url },
                tags_ids => [ $tag->{ tags_id } ],
                feeds    => [ $_->{ feed_url }, $_->{ custom_feed_url }, 'http://192.168.168.168:123456/456789/feed' ]
            }
        } @{ $sites }
    ];

    my $r = test_post( '/api/v2/media/create', $input );

    is( scalar( @{ $r->{ errors } } ), 0, "media/create update errors" );
    is( scalar( @{ $r->{ media } } ), scalar( @{ $sites } ), "media/create update media returned" );

    for my $site ( @{ $sites } )
    {
        my $medium = $db->query( "select * from media where name = ?", $site->{ name } )->hash
          || die( "unable to find medium for site $site->{ name }" );
        my $feeds = $db->query( "select * from feeds where media_id = ? order by feeds_id", $medium->{ media_id } )->hashes;
        is( scalar( @{ $feeds } ), 2, "media/create update $site->{ name } num feeds" );

        is( $feeds->[ 0 ]->{ url }, $site->{ feed_url },        "media/create update $site->{ name } default feed url" );
        is( $feeds->[ 1 ]->{ url }, $site->{ custom_feed_url }, "media/create update $site->{ name } custom feed url" );

        for my $feed ( @{ $feeds } )
        {
            is( $feed->{ feed_type },   'syndicated', "$site->{ name } feed type" );
            is( $feed->{ feed_status }, 'active',     "$site->{ name } feed status" );
        }

        my ( $tag_exists ) = $db->query( <<SQL, $medium->{ media_id }, $tag->{ tags_id } )->flat;
select * from media_tags_map where media_id = \$1 and tags_id = \$2
SQL
        ok( $tag_exists, "media/create update $site->{ name } tag exists" );
    }
}

# test media/update call
sub test_media_update($$)
{
    my ( $db, $sites ) = @_;

    # test that request with no media_id returns an error
    test_put( '/api/v2/media/update', {}, 1 );

    # test that request with list returns an error
    test_put( '/api/v2/media/update', [ { media_id => 1 } ], 1 );

    my $medium = $db->query( "select * from media where name = ?", $sites->[ 0 ]->{ name } )->hash;

    my $fields = [ qw/media_id name url content_delay editor_notes public_notes foreign_rss_links/ ];

    # test just name change
    my $r = test_put( '/api/v2/media/update', { media_id => $medium->{ media_id }, name => "$medium->{ name } FOO" } );
    is( $r->{ success }, 1, "media/update name success" );

    my $updated_medium = $db->require_by_id( 'media', $medium->{ media_id } );
    is( $updated_medium->{ name }, "$medium->{ name } FOO", "media update name" );
    $medium->{ name } = $updated_medium->{ name };
    map { is( $updated_medium->{ $_ }, $medium->{ $_ }, "media update name field $_" ) } @{ $fields };

    # test all other fields
    $medium = {
        media_id          => $medium->{ media_id },
        url               => "http://url.update/",
        name              => 'name update',
        foreign_rss_links => 1,
        content_delay     => 100,
        editor_notes      => 'editor_notes update',
        public_notes      => 'public_notes update'
    };

    $r = test_put( '/api/v2/media/update', $medium );
    is( $r->{ success }, 1, "media/update all success" );

    my $updated_medium = $db->require_by_id( 'media', $medium->{ media_id } );
    map { is( $updated_medium->{ $_ }, $medium->{ $_ }, "media update name field $_" ) } @{ $fields };
}

# test media/create  end point
sub test_media_create($)
{
    my ( $db ) = @_;

    my $site_names = [ map { "media_create_site_$_" } ( 1 .. 5 ) ];

    my $hs = start_media_create_hash_server( $site_names );

    my $sites = [];
    for my $site_name ( @{ $site_names } )
    {
        push(
            @{ $sites },
            {
                name            => $site_name,
                url             => $hs->page_url( $site_name ),
                feed_url        => $hs->page_url( "$site_name/feed" ),
                custom_feed_url => $hs->page_url( "$site_name/custom_feed" )
            }
        );
    }

    # delete existing entries in media_rescraping so that we can wait for it to be empty in test_for_scraped_feeds()
    $db->query( "truncate table media_rescraping" );

    # test that non-list returns an error
    test_post( '/api/v2/media/create', {}, 1 );

    # test that single element without url returns an error
    test_post( '/api/v2/media/create', [ { url => 'http://foo.com' }, { name => "bar" } ], 1 );

    # simple test for creation of url only medium
    my $first_site   = $sites->[ 0 ];
    my $r            = test_post( '/api/v2/media/create', [ { url => $first_site->{ url } } ] );
    my $first_medium = $db->query( "select * from media where name = \$1", $first_site->{ name } )->hash;
    is( scalar( @{ $r->{ media } } ), 1, "media/create url number returned" );
    ok( $first_medium, "media/create url found medium with matching title" );
    _compare_fields( "media/create url", $r->{ media }->[ 0 ], $first_medium, [ qw/media_id name url/ ] );

    # test that create reuse the same media source we just created
    $r = test_post( '/api/v2/media/create', [ { url => $first_site->{ url } } ] );
    is( scalar( @{ $r->{ media } } ), 1, "media/create url number returned" );
    _compare_fields( "media/create url dup", $r->{ media }->[ 0 ], $first_medium, [ qw/media_id name url/ ] );

    # add all media sources in sites, plus one which should return a 404
    my $input = [ map { { url => $_->{ url } } } ( @{ $sites }, { url => 'http://192.168.168.168:123456/456789' } ) ];
    $r = test_post( '/api/v2/media/create', $input );
    is( scalar( @{ $r->{ media } } ), scalar( @{ $sites } ), "media/create mixed urls number returned" );
    is( scalar( @{ $r->{ errors } } ), 1, "media/create mixed urls errors returned" );
    ok( $r->{ errors }->[ 0 ] =~ /Unable to fetch medium url/, "media/create mixed urls error message" );

    for my $site ( @{ $sites } )
    {
        my $url = $site->{ url };
        my $db_m = $db->query( "select * from media where url = ?", $url )->hash;
        ok( $db_m, "media/create mixed urls medium found for in db url $url" );
        my ( $r_m ) = grep { $_->{ url } eq $url } @{ $r->{ media } };
        ok( $r_m, "media/create mixed urls medium found in api response for url $url" );
        _compare_fields( "media/create mixed urls $url", $r_m, $db_m, [ qw/media_id name url/ ] );
        if ( $url eq $first_site->{ url } )
        {
            is( $r_m->{ media_id }, $first_medium->{ media_id }, "media/create mixed urls existing medium" );
        }
    }

    test_for_scraped_feeds( $db, $sites );

    test_media_create_update( $db, $sites );

    test_media_update( $db, $sites );

    $hs->stop();
}

# test various media/ calls
sub test_media($$)
{
    my ( $db, $test_media ) = @_;

    my $expected_media = [ grep { $_->{ name } && $_->{ name } =~ /^media_/ } values( %{ $test_media } ) ];

    my $media = test_get( '/api/v2/media/list', {} );
    is( scalar( @{ $media } ), $NUM_MEDIA, "media/list num of media" );
    for my $medium ( @{ $media } )
    {
        my ( $expected_medium ) = grep { $_->{ name } eq $medium->{ name } } @{ $expected_media };
        ok( $expected_medium, "media/list found name amount expected media" );

        my $fields = [ qw/name url/ ];
        map { is( $medium->{ $_ }, $expected_medium->{ $_ }, "media/list: field $_" ) } @{ $fields };
    }

    test_media_create( $db );
}

# test parts of the ai that only require reading, so we can test these all in one chunk
sub test_api($)
{
    my ( $db ) = @_;

    $_api_token = MediaWords::Test::DB::create_test_user( $db );

    my $media = MediaWords::Test::DB::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    MediaWords::Test::DB::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    test_stories_public_list( $db, $media );
    test_auth_profile( $db );
    test_media( $db, $media );

}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_api,
        [ 'solr_standalone', 'job_broker:rabbitmq', 'rescrape_media' ] );

    done_testing();
}

main();
