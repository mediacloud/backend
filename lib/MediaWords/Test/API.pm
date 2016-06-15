package MediaWords::Test::API;
use strict;
use warnings;
use MediaWords::Test::DB;

BEGIN
{
    use Catalyst::Test ( 'MediaWords' );
}

my $TEST_API_KEY;

sub create_test_api_user
{
    my $db = shift;
    $TEST_API_KEY = MediaWords::Test::DB::create_test_user( $db );
}

sub call_test_api
{
    my $base_url = shift;
    my $url      = _api_request_url( $base_url->{ path }, $base_url->{ params } );
    my $response = request( $url );
}

sub _api_request_url($;$)
{
    my ( $path, $params ) = @_;
    my $uri = URI->new( $path );
    $uri->query_param( 'key' => $TEST_API_KEY );
    if ( $params )
    {
        foreach my $key ( keys %{ $params } )
        {
            $uri->query_param( $key => $params->{ $key } );
        }
    }
    return $uri->as_string;
}

1;
