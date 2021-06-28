package MediaWords::Test::API;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Catalyst::Test 'MediaWords';
use HTTP::Request;
use Test::More;

use URI;
use URI::QueryParam;

use MediaWords::Util::Web;
use MediaWords::Util::ParseJSON;
use MediaWords::Test::DB::Create::User;

my $_test_api_key;

# list of api urls requested by this process; used by get_untested_api_urls() to get a list of api urls that have not
# been called by this process
my $_api_requested_urls_lookup = {};

sub setup_test_api_key($)
{
    my ( $db ) = @_;

    if ( !$_test_api_key )
    {
        $_test_api_key = MediaWords::Test::DB::Create::User::create_test_user( $db, 'api_key' );

        $db->query( <<SQL
            WITH api_key_user AS (
                SELECT auth_users_id
                FROM auth_users
                WHERE full_name = 'api_key'
            ),

            admin_role AS (
                SELECT auth_roles_id
                FROM auth_roles
                WHERE role = 'admin'
            )

            INSERT INTO auth_users_roles_map (
                auth_users_id, auth_roles_id
            )
                SELECT
                    auth_users_id,
                    auth_roles_id
                FROM api_key_user
                    CROSS JOIN admin_role

            ON CONFLICT (auth_users_id, auth_roles_id) DO NOTHING
SQL
        );
    }

    return $_test_api_key;
}

sub get_test_api_key()
{
    # require calls to setup_test_api_key first so that we don't have to make the user pass the db into this
    # and dependan calls
    die( "must call setup_test_api_key first" ) unless ( $_test_api_key );

    return $_test_api_key;
}

#  test that we got a valid response,
# that the response is valid json, and that the JSON response is not an error response.  Return
# the decoded json.  If $expect_error is true, test for expected error response.
sub test_request_response($$;$)
{
    my ( $label, $response, $expect_error ) = @_;

    $expect_error ||= 0;

    my $url = $response->request->url;

    my $url_path = URI->new( $url )->path;
    $url_path =~ s/\/\d+//;
    $_api_requested_urls_lookup->{ $url_path } = 1;

    is( $response->is_success, !$expect_error, "HTTP response status OK for $label:\n" . $response->decoded_content );

    my $data = eval { MediaWords::Util::ParseJSON::decode_json( $response->decoded_content ) };

    ok( $data, "decoded JSON for $label (json error: $@)" );

    if ( $expect_error )
    {
        ok( ( ( ref( $data ) eq ref( {} ) ) && $data->{ error } ), "response is an error for $label:\n" . Dumper( $data ) );
    }
    else
    {
        ok(
            !( ( ref( $data ) eq ref( {} ) ) && $data->{ error } ),
            "response is not an error for $label:\n" . Dumper( $data )
        );
    }

    return $data;
}

# execute Catalyst::Test::request() with an HTTP request with the given data as JSON content.
# call test_request_response() on the result and return the decoded JSON data
sub test_data_request($$$;$)
{
    my ( $method, $url, $data, $expect_error ) = @_;

    $expect_error ||= 0;

    my $uri = URI->new( $url );
    unless ( $uri->query_param( 'key' ) )
    {
        $uri->query_param( 'key', get_test_api_key() );
    }
    $url = $uri->as_string;

    my $json = MediaWords::Util::ParseJSON::encode_json( $data );

    my $request = HTTP::Request->new( $method, $url );
    $request->header( 'Content-Type' => 'application/json; charset=UTF-8' );
    $request->content( $json );

    my $label = "method=$method URL=$url data=$json expect_error=$expect_error";

    # Catalyst::Test::request()
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

# execute Catalyst::Test::request() on the given url with the given params and then call test_request_response()
# to test and return the decode JSON data
sub test_get($;$$)
{
    my ( $url, $params, $expect_error ) = @_;

    my $uri = URI->new( $url );

    foreach my $param_key ( keys %{ $params } )
    {
        my $param_value = $params->{ $param_key };
        $uri->query_param( $param_key, $param_value );
    }

    unless ( $uri->query_param( 'key' ) )
    {
        $uri->query_param( 'key', get_test_api_key() );
    }

    $url = $uri->as_string;

    # Catalyst::Test::request()
    return test_request_response( $url, request( $url ), $expect_error );
}

# query the catalyst context to get a list of urls of all api end points
sub get_api_urls()
{
    # use any old request just to get the $c
    # Catalyst::Test::ctx_request()
    my ( $res, $c ) = ctx_request( '/status' );

    # this chunk of code that pulls url end points out of catalyst relies on ugly reverse engineering of the
    # private internals of the Catalyst::DispatchType::Chained and Catalyst::DispathType::Path, but it is as
    # far as I can tell the only way to get catalyst to tell us what urls it is serving.

    my $chained_actions = $c->dispatcher->dispatch_type( 'Chained' )->_endpoints;
    my $chained_urls = [ map { "/$_->{ reverse }" } @{ $chained_actions } ];

    my $path_actions = [ values( %{ $c->dispatcher->dispatch_type( 'Path' )->_paths } ) ];
    my $path_urls = [ map { $_->[ 0 ]->private_path } @{ $path_actions } ];

    my $api_urls = [ sort grep { m~/api/~ } ( @{ $path_urls }, @{ $chained_urls } ) ];

    return $api_urls;
}

1;
