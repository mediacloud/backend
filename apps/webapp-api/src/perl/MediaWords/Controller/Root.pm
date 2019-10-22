package MediaWords::Controller::Root;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use base 'Catalyst::Controller';

use Encode;
use HTTP::Status qw(:constants);

use MediaWords::Util::ParseJSON;

# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
__PACKAGE__->config->{ namespace } = '';

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    my $message = <<EOF;
Welcome to Media Cloud API!

To get your API key and see the spec, head to:

https://github.com/berkmancenter/mediacloud/blob/master/doc/api_2_0_spec/api_2_0_spec.md

This particular API endpoint ('/') is not authenticated and does nothing.
EOF

    my $response = { 'error' => $message };

    # Catalyst expects bytes
    my $json = encode_utf8( MediaWords::Util::ParseJSON::encode_json( $response ) );

    $c->response->status( HTTP_UNAUTHORIZED );
    $c->response->content_type( 'application/json; charset=UTF-8' );
    $c->response->content_length( bytes::length( $json ) );
    $c->response->body( $json );
}

sub default : Private
{
    my ( $self, $c ) = @_;

    $c->response->status( HTTP_NOT_FOUND );
    die "API endpoint was not found";
}

1;
