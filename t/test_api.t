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
use Readonly;
use Test::More;
use URI::Escape;

use MediaWords::Test::DB;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

my $_api_token;

# call Catalyst::Test::request with the given hashref of params encoded into the url.
# add a key param for the key stored in $_api_token.  test that we got a valid response,
# that the response is valid json, and that the json response is not an error response.  Return
# the decoded json.
sub test_request($;$)
{
    my ( $url, $params ) = @_;

    $params //= {};
    $params->{ key } //= $_api_token;

    my $encoded_params = join( "&", map { $_ . '=' . uri_escape( $params->{ $_ } ) } keys( %{ $params } ) );

    my $full_url = "$url?$encoded_params";

    my $response = request( $full_url );

    ok( $response->is_success, "valid HTTP response for $full_url" );

    my $data = MediaWords::Util::JSON::decode_json( $response->content );

    ok( $data, "decoded json for $full_url" );

    ok( !( ( ref( $data ) eq ref( {} ) ) && $data->{ error } ), "response is not an error for $full_url" );

    return $data;
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
sub test_stories_public_list($)
{
    my ( $db, $media ) = @_;

    my $stories = test_request( '/api/v2/stories_public/list', { q => 'title:story*', rows => 100000 } );

    my $expected_num_stories = $NUM_MEDIA * $NUM_FEEDS_PER_MEDIUM * $NUM_STORIES_PER_FEED;
    my $got_num_stories      = scalar( @{ $stories } );

    my $title_stories_lookup = {};
    map { $title_stories_lookup->{ $_->{ title } } = $_ } @{ $stories };

    for my $i ( 0 .. $expected_num_stories - 1 )
    {
        my $expected_title = "story story_$i";
        my $story          = $title_stories_lookup->{ $expected_title };
        ok( $story, "found story with title '$expected_title'" );
        test_story_fields( $story, "all stories: story $i" );
    }

    my $search_result =
      test_request( '/api/v2/stories_public/list', { q => 'stories_id:' . $stories->[ 0 ]->{ stories_id } } );
    is( scalar( @{ $search_result } ), 1, "stories_public search: count" );
    is( $search_result->[ 0 ]->{ stories_id }, $stories->[ 0 ]->{ stories_id }, "stories_public search: stories_id match" );
    test_story_fields( $search_result->[ 0 ], "story_public search" );

    my $stories_single = test_request( '/api/v2/stories_public/single/' . $stories->[ 1 ]->{ stories_id } );
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
    my $profile = test_request( "/api/v2/auth/profile" );

    for my $field ( qw/email auth_users_id weekly_request_items_limit non_public_api notes active weekly_requests_limit/ )
    {
        is( $profile->{ $field }, $expected_user->{ $field }, "auth profile $field" );
    }
}

sub test_api($)
{
    my ( $db ) = @_;

    $_api_token = MediaWords::Test::DB::create_test_user( $db );

    my $media = MediaWords::Test::DB::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    MediaWords::Test::DB::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    test_stories_public_list( $db );
    test_auth_profile( $db );

}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_api, [ qw/solr_standalone/ ] );

    done_testing();
}

main();
