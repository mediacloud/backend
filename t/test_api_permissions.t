#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin";
    use lib "$FindBin::Bin/../lib";
    use Catalyst::Test 'MediaWords';
}

use MediaWords::CommonLibs;
use Modern::Perl "2015";

use HTTP::Request::Common;
use JSON;
use List::MoreUtils "uniq";
use List::Util "shuffle";
use Readonly;
use Test::More;
use URI::Escape;

use MediaWords::Test::DB;

# public and private key users
my $_public_user;
my $_private_user;

# this hash maps each api end point to the kind of permission it should have: public, private, or topics
my $_url_permission_types = {
    '/api/v2/auth/single' => 'private',
    '/api/v2/auth/single_GET' => 'private',
    '/api/v2/controversies/list' => 'public',
    '/api/v2/controversies/list_GET' => 'public',
    '/api/v2/controversies/single' => 'public',
    '/api/v2/controversies/single_GET' => 'public',
    '/api/v2/controversy_dumps/list' => 'public',
    '/api/v2/controversy_dumps/list_GET' => 'public',
    '/api/v2/controversy_dumps/single' => 'public',
    '/api/v2/controversy_dumps/single_GET' => 'public',
    '/api/v2/controversy_dump_time_slices/list' => 'public',
    '/api/v2/controversy_dump_time_slices/list_GET' => 'public',
    '/api/v2/controversy_dump_time_slices/single' => 'public',
    '/api/v2/controversy_dump_time_slices/single_GET' => 'public',
    '/api/v2/crawler/add_feed_download' => 'private',
    '/api/v2/crawler/add_feed_download_PUT' => 'private',
    '/api/v2/downloads/list' => 'private',
    '/api/v2/downloads/list_GET', => 'private',
    '/api/v2/downloads/single' => 'private',
    '/api/v2/downloads/single_GET' => 'private',
    '/api/v2/feeds/list' => 'public',
    '/api/v2/feeds/list_GET' => 'public',
    '/api/v2/feeds/single' => 'public',
    '/api/v2/feeds/single_GET' => 'public',
    '/api/v2/mc_rest_simpleobject/list' => 'public',
    '/api/v2/mc_rest_simpleobject/list_GET' => 'public',
    '/api/v2/mc_rest_simpleobject/single' => 'public',
    '/api/v2/mc_rest_simpleobject/single_GET' => 'public',
    '/api/v2/mediahealth/list' => 'public',
    '/api/v2/mediahealth/list_GET' => 'public',
    '/api/v2/mediahealth/single' => 'public',
    '/api/v2/mediahealth/single_GET' => 'public',
    '/api/v2/media/list' => 'public',
    '/api/v2/media/list_GET' => 'public',
    '/api/v2/media/single' => 'public',
    '/api/v2/media/single_GET' => 'public',
    '/api/v2/sentences/count' => 'public',
    '/api/v2/sentences/count_GET' => 'public',
    '/api/v2/sentences/field_count' => 'public',
    '/api/v2/sentences/field_count_GET' => 'public',
    '/api/v2/sentences/list' => 'private',
    '/api/v2/sentences/list_GET' => 'private',
    '/api/v2/sentences/put_tags' => 'private',
    '/api/v2/sentences/put_tags_PUT' => 'private',
    '/api/v2/sentences/single' => 'private',
    '/api/v2/sentences/single_GET' => 'private',
    '/api/v2/storiesbase/count' => 'public',
    '/api/v2/storiesbase/count_GET' => 'public',
    '/api/v2/storiesbase/list' => 'public',
    '/api/v2/storiesbase/list_GET' => 'public',
    '/api/v2/storiesbase/single' => 'public',
    '/api/v2/storiesbase/single_GET' => 'public',
    '/api/v2/storiesbase/word_matrix' => 'public',
    '/api/v2/storiesbase/word_matrix_GET' => 'public',
    '/api/v2/stories/cluster_stories' => 'private',
    '/api/v2/stories/cluster_stories_GET' => 'private',
    '/api/v2/stories/corenlp' => 'private',
    '/api/v2/stories/count' => 'public',
    '/api/v2/stories/count_GET' => 'public',
    '/api/v2/stories/fetch_bitly_clicks' => 'private',
    '/api/v2/stories/list' => 'private',
    '/api/v2/stories/list_GET' => 'private',
    '/api/v2/stories_public/count' => 'public',
    '/api/v2/stories_public/count_GET' => 'public',
    '/api/v2/stories_public/list' => 'public',
    '/api/v2/stories_public/list_GET' => 'public',
    '/api/v2/stories_public/single' => 'public',
    '/api/v2/stories_public/single_GET' => 'public',
    '/api/v2/stories_public/word_matrix' => 'public',
    '/api/v2/stories_public/word_matrix_GET' => 'public',
    '/api/v2/stories/put_tags' => 'private',
    '/api/v2/stories/put_tags_PUT' => 'private',
    '/api/v2/stories/single' => 'private',
    '/api/v2/stories/single_GET' => 'private',
    '/api/v2/stories/word_matrix' => 'public',
    '/api/v2/stories/word_matrix_GET' => 'public',
    '/api/v2/tag_sets/list' => 'public',
    '/api/v2/tag_sets/list_GET' => 'public',
    '/api/v2/tag_sets/single' => 'public',
    '/api/v2/tag_sets/single_GET' => 'public',
    '/api/v2/tag_sets/update' => 'private',
    '/api/v2/tag_sets/update_PUT' => 'private',
    '/api/v2/tags/list' => 'public',
    '/api/v2/tags/list_GET' => 'public',
    '/api/v2/tags/single' => 'public',
    '/api/v2/tags/single_GET' => 'public',
    '/api/v2/tags/update' => 'private',
    '/api/v2/tags/update_PUT' => 'private',
    '/api/v2/topics/focal_set_definitions/create_GET' => 'topics',
    '/api/v2/topics/focal_set_definitions/delete_PUT' => 'topics',
    '/api/v2/topics/focal_set_definitions/list_GET' => 'topics',
    '/api/v2/topics/focal_set_definitions/update_PUT' => 'topics',
    '/api/v2/topics/focal_sets/list_GET' => 'topics',
    '/api/v2/topics/foci/list_GET' => 'topics',
    '/api/v2/topics/focus_definitions/create_GET' => 'topics',
    '/api/v2/topics/focus_definitions/delete_PUT' => 'topics',
    '/api/v2/topics/focus_definitions/list_GET' => 'topics',
    '/api/v2/topics/focus_definitions/update_PUT' => 'topics',
    '/api/v2/topics/list' => 'public',
    '/api/v2/topics/list_GET' => 'public',
    '/api/v2/topics/media/list_GET' => 'topics',
    '/api/v2/topics/permissions/list_GET' => 'topics',
    '/api/v2/topics/permissions/user_list_GET' => 'topics',
    '/api/v2/topics/single' => 'public',
    '/api/v2/topics/single_GET' => 'public',
    '/api/v2/topics/snapshots/generate_GET' => 'topics',
    '/api/v2/topics/snapshots/list_GET' => 'topics',
    '/api/v2/topics/stories/count_GET' => 'topics',
    '/api/v2/topics/stories/list_GET' => 'topics',
    '/api/v2/topics/timespans/list_GET' => 'topics',
    '/api/v2/wc/list' => 'public',
    '/api/v2/wc/list_GET' => 'public',
};

# request GET, POST, and PUT methods from the url; return all responses that are not a 405
sub request_all_methods($;$)
{
    my ( $url, $params ) = @_;

    $params ||= {};

    my $params_url = "$url?" . join( '&', map { "$_=" . uri_escape( $params->{ $_ } ) } keys( %{ $params } ) );

    my $responses = [ map { request( $_ ) } ( PUT( $params_url ), POST( $params_url ), GET( $params_url) ) ];

    return [ grep { $_->code != 405 } @{ $responses } ];
}

# make sure that the path requires at least a public key
sub test_key_required($)
{
    my ( $url ) = @_;

    my $responses = request_all_methods( $url );

    for my $response ( @{ $responses } )
    {
        my $method = $response->request->method;
        is( $response->code, 403, "test_key_required 403: $url $method" );
        ok( $response->decoded_content =~ /Invalid API key/, "test_key_required message: $url $method" );
    }
}

# query the catalyst context to get a list of urls of all api end points
sub get_api_urls()
{
   # use any old request just to get the $c
    my ( $res, $c ) = ctx_request( '/admin/topics/list' );

    # getting the _paths private attribute of the dispatch_type is the only way I can find to get
    # catalyst to give me all of the paths implemented by the web app
    my $dispatch_type = $c->dispatcher->dispatch_type( 'Path' );

    my $paths = [ values( %{ $dispatch_type->_paths } ) ];

    my $path_urls = [ map { $_->[0]->private_path() } @{ $paths } ];

    my $api_urls = [ grep { m~/api/~ } @{ $path_urls } ];

    # $api_paths = [ '/api/v2/stories/put_tags_PUT' ];

    return $api_urls;
}

sub request_all_methods_as_user($$)
{
    my ( $url, $user ) = @_;

    return request_all_methods( $url, { key => $user->{ api_token } } );
}

sub test_public_permission($)
{
    my ( $url ) = @_;

    my $public_responses = request_all_methods_as_user( $url, $_public_user );

    map { ok( $_->code != 403, "public user accepted for public url $url: " . $_->as_string ) } @{ $public_responses };

    my $private_responses = request_all_methods_as_user( $url, $_private_user );

    map { ok( $_->code != 403, "private user accepted for public url $url: " . $_->as_string ) } @{ $private_responses };
}

sub test_private_permission($)
{
}

sub test_topics_permission($)
{
}

# lookup the permission type in $_url_permission_types and make sure that the url follows the rules for its
# permission type
sub test_permission($)
{
    my ( $url )= @_;

    my $permission_type = $_url_permission_types->{ $url };

    ok( $permission_type, "permission type exists for $url");

    if (    $permission_type eq 'public' )  { test_public_permission( $url ) }
    elsif ( $permission_type eq 'private' ) { test_private_permission( $url ) }
    elsif ( $permission_type eq 'topics' )  { test_topics_permission( $url ) }
    else                                    { ok( undef, "unknown permission type '$permission_type' for $url" ) }
}

# add user of type 'public' or 'private' and return the resulting auth_users hash;
sub add_test_user($$)
{
    my ( $db, $type ) = @_;

    my $email = $type . '@foo.bar';
    my $password = '123456789';
    my $private_api = ( $type eq 'private' ) ? 1 : 0;

    my $error = MediaWords::DBI::Auth::add_user_or_return_error_message(
        $db, $email, $type,
        $type, [], 1,
        $password,  $password, $private_api,
        1000000, 1000000
    );

    die( "error adding $type user: $error" ) if ( $error );

    return $db->query( "select * from auth_users where email = ?", $email )->hash;
}

# for each path, test to make sure that at least a public key is required, then check to make sure the expected
# permission is required for the path
sub test_permissions($$)
{
    my ( $db, $api_urls ) = @_;

    $_public_user = add_test_user( $db, 'public' );
    $_private_user = add_test_user( $db, 'private' );

    for my $url ( @{ $api_urls } )
    {
        test_key_required( $url );
        test_permission( $url );
    }
}

sub main()
{
    MediaWords::Test::DB::test_on_test_database(
        sub {

            my $db = shift;

            my $api_urls = get_api_urls( );

            test_permissions( $db, $api_urls );

            done_testing();
        }
    );
}

main();
