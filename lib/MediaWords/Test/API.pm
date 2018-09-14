package MediaWords::Test::API;

use strict;
use warnings;

use Catalyst::Test 'MediaWords';
use HTTP::Request;
use Regexp::Common;
use Test::More;

use URI;
use URI::QueryParam;

use MediaWords::CommonLibs;
use MediaWords::Util::Web;

my $_test_api_key;

# list of api urls requested by this process; used by get_untested_api_urls() to get a list of api urls that have not
# been called by this process
my $_api_requested_urls_lookup = {};

sub setup_test_api_key($)
{
    my ( $db ) = @_;

    if ( !$_test_api_key )
    {
        $_test_api_key = MediaWords::Test::DB::Create::create_test_user( $db, 'api_key' );

        #         $db->query( <<SQL );
        # insert into auth_users_roles_map ( auth_users_id, auth_roles_id )
        #     select a.auth_users_id, r.auth_roles_id
        #         from auth_users a, auth_roles r
        #         where
        #             a.full_name = 'api_key' and
        #             r.role = 'admin' and
        #             not exists
        #             ( select 1 from auth_users_roles_map
        #                 where auth_users_id = a.auth_users_id and auth_roles_id = r.auth_roles_id )
        # SQL
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

# test that all fields with purely number responses return JSON numbers
sub validate_number_fields($$)
{
    my ( $label, $json ) = @_;

    while ( $json =~ /("[^"]+"\s*:\s*"[\d]+")/g )
    {
        ok( 0, "$label number field has been stringified: $1" );
        WARN( "json: " . substr( $json, 0, 2048 ) );
        die();
    }
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

    my $data = eval { MediaWords::Util::JSON::decode_json( $response->decoded_content ) };

    ok( $data, "decoded JSON for $label (json error: $@)" );

    validate_number_fields( $label, $response->decoded_content );

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

    my $json = MediaWords::Util::JSON::encode_json( $data );

    my $request = HTTP::Request->new( $method, $url );
    $request->header( 'Content-Type' => 'application/json' );
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

# test that got_rows matches expected_rows by checking for the same number of elements, the matching up rows in
# got_rows and expected_rows and testing whether each field in $test_fields matches
sub rows_match($$$$$)
{
    my ( $label, $got_rows, $expected_rows, $id_field, $test_fields ) = @_;

    ok( defined( $got_rows ), "$label got_rows defined" );

    # just return if the number is not equal to avoid printing a bunch of uncessary errors
    is( scalar( @{ $got_rows } ), scalar( @{ $expected_rows } ), "$label number of rows" ) || return;

    my $expected_row_lookup = {};
    map { $expected_row_lookup->{ $_->{ $id_field } } = $_ } @{ $expected_rows };

    for my $got_row ( @{ $got_rows } )
    {
        my $id           = $got_row->{ $id_field };
        my $expected_row = $expected_row_lookup->{ $id };

        # don't try to test individual fields if the row does not exist
        ok( $expected_row, "$label row with id $got_row->{ $id_field } is expected" ) || next;

        for my $field ( @{ $test_fields } )
        {
            my $got      = $got_row->{ $field }      // '';
            my $expected = $expected_row->{ $field } // '';

            ok( exists( $got_row->{ $field } ), "$label field $field exists" );

            # if got and expected are both numers, test using number equality so that 4 == 4.0
            if ( $expected =~ /^$RE{ num }{ real }$/ && $got =~ /^$RE{ num }{ real }$/ )
            {
                my $label = "$label field $field ($id_field: $id): got $got expected $expected";

                # for ints, test equality; if one is a float, use a small delta so that 0.333333 == 0.33333
                if ( $expected =~ /^$RE{ num }{ int }$/ && $got =~ /^$RE{ num }{ int }$/ )
                {
                    ok( $got == $expected, $label );
                }
                else
                {
                    ok( abs( $got - $expected ) < 0.00001, $label );
                }
            }

            # If expected looks like a database boolean, compare it as such
            elsif ( $expected eq 'f' or $expected eq 't' or $got eq 'f' or $got eq 't' )
            {
                $expected = normalize_boolean_for_db( $expected );
                $got      = normalize_boolean_for_db( $got );
                is( $got, $expected, $label );
            }
            else
            {
                is( $got, $expected, "$label field $field ($id_field: $id)" );
            }
        }
    }

}

# given the response from an api call, fetch the referred row from the given table in the database
# and verify that the fields in the given input match what's in the database
sub validate_db_row($$$$$)
{
    my ( $db, $table, $response, $input, $label ) = @_;

    my $id_field = "${ table }_id";

    ok( $response->{ $id_field } > 0, "$label $id_field returned" );
    my $db_row = $db->find_by_id( $table, $response->{ $id_field } );
    ok( $db_row, "$label row found in db" );

    for my $key ( keys( %{ $input } ) )
    {
        my $got      = $db_row->{ $key };
        my $expected = $input->{ $key };

        # If expected looks like a database boolean, compare it as such
        if ( $expected eq 'f' or $expected eq 't' or $got eq 'f' or $got eq 't' )
        {
            $expected = normalize_boolean_for_db( $expected );
            $got      = normalize_boolean_for_db( $got );
        }

        is( $got, $expected, "$label field $key" );
    }
}

# query the catalyst context to get a list of urls of all api end points
sub get_api_urls()
{
    # use any old request just to get the $c
    # Catalyst::Test::ctx_request()
    my ( $res, $c ) = ctx_request( '/admin/topics/list' );

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
