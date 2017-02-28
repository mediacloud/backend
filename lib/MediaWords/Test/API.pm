package MediaWords::Test::API;

use strict;
use warnings;

use Catalyst::Test 'MediaWords';
use HTTP::Request;
use Test::More;
use URI::Escape;

use MediaWords::CommonLibs;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(test_request_response test_data_request test_get test_put test_post rows_match);

my $_test_api_key;

sub setup_test_api_key($)
{
    my ( $db ) = @_;

    $_test_api_key ||= MediaWords::Test::DB::create_test_user( $db );

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
# that the response is valid json, and that the json response is not an error response.  Return
# the decoded json.  If $expect_error is true, test for expected error response.
sub test_request_response($$;$)
{
    my ( $label, $response, $expect_error ) = @_;

    my $url = $response->request->url;

    is( $response->is_success, !$expect_error, "HTTP response status OK for $label:\n" . $response->as_string );

    my $data = eval { MediaWords::Util::JSON::decode_json( $response->content ) };

    ok( $data, "decoded json for $label (json error: $@)" );

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

# execute Catalyst::Test::request with an HTTP request with the given data as json content.
# call test_request_response() on the result and return the decoded json data
sub test_data_request($$$;$)
{
    my ( $method, $url, $data, $expect_error ) = @_;

    my $api_token = get_test_api_key();

    $url = $url =~ /\?/ ? "$url&key=$api_token" : "$url?key=$api_token";

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

    my $api_token = get_test_api_key();

    $params //= {};
    $params->{ key } //= $api_token;

    my $encoded_params = join( "&", map { $_ . '=' . uri_escape( $params->{ $_ } ) } keys( %{ $params } ) );

    my $full_url = "$url?$encoded_params";

    return test_request_response( $full_url, request( $full_url ), $expect_error );
}

# test that got_rows matches expected_rows by checking for the same number of elements, the matching up rows in
# got_rows and expected_rows and testing whether each field in $test_fields matches
sub rows_match($$$$$)
{
    my ( $label, $got_rows, $expected_rows, $id_field, $test_fields ) = @_;

    # just return if the number is not equal to avoid printing a bunch of uncessary errors
    is( scalar( @{ $got_rows } ), scalar( @{ $expected_rows } ), "$label number of rows" ) || return;

    my $expected_row_lookup = {};
    map { $expected_row_lookup->{ $_->{ $id_field } } = $_ } @{ $expected_rows };

    for my $got_row ( @{ $got_rows } )
    {
        my $expected_row = $expected_row_lookup->{ $got_row->{ $id_field } };

        # don't try to test individual fields if the row does not exist
        ok( $expected_row, "$label row with id $got_row->{ $id_field } is expected" ) || next;

        for my $field ( @{ $test_fields } )
        {
            is( $got_row->{ $field }, $expected_row->{ $field }, "$label field $field" );
        }
    }

}

1;
