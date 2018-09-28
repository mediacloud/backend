package MediaWords::Controller::Api::V2::MC_Controller_REST;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth;
use MediaWords::Util::ParseJSON;

use strict;
use warnings;
use base 'Catalyst::Controller::REST';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use HTTP::Status qw(:constants);
use Encode;

=head1 NAME

MediaWords::Controller::Api::V2::MC_Controller_REST

=head1 DESCRIPTION

Light wrapper class over Catalyst::Controller::REST

=head1 METHODS

=cut

=head2 index

=cut

BEGIN { extends 'Catalyst::Controller::REST' }

# Python functions for encoding / decoding JSON expect specific types of
# parameters (e.g. boolean as second parameter), but Catalyst::Controller::REST
# passes three parameters to serializers in all cases, so we define small
# serialization wrappers here
sub _encode_json($$$)
{
    my ( $object, $controller, $c ) = @_;
    my $json = MediaWords::Util::ParseJSON::encode_json( $object );

    # Catalyst expects bytes
    $json = encode_utf8( $json );

    return $json;
}

sub _decode_json($$$)
{
    my ( $json, $controller, $c ) = @_;
    return MediaWords::Util::ParseJSON::decode_json( $json );
}

__PACKAGE__->config(
    'default'   => 'application/json; charset=UTF-8',
    'stash_key' => 'rest',
    'map'       => {
        'text/xml'         => 'XML::Simple',    #
        'application/json' => [                 #
            'Callback',                         #
            {                                   #
                serialize   => \&_encode_json,    #
                deserialize => \&_decode_json,    #
            }    #
        ],       #
        'application/json; charset=UTF-8' => [    #
            'Callback',                           #
            {                                     #
                serialize   => \&_encode_json,    #
                deserialize => \&_decode_json,    #
            }    #
        ],       #
        'text/x-json' => [    #
            'Callback',       #
            {                 #
                serialize   => \&_encode_json,    #
                deserialize => \&_decode_json,    #
            }    #
        ],       #
    }
);

sub serialize : ActionClass('Serialize')
{
    # Just calls parent
}

# catch Catalyst exceptions (controller actions that have died); report them in JSON back to the client.
# also add link data to entity, including finding or creating a next_link_id for the current
sub end : Private
{
    my ( $self, $c ) = @_;

    map { $c->log->error( $_ ) } @{ $c->error } if ( $c->error );

    my $errors = [];
    push( @{ $errors }, @{ $c->error } ) if ( $c->error );
    push( @{ $errors }, @{ $c->stash->{ auth_errors } } ) if ( $c->stash->{ auth_errors } );

    if ( scalar( @{ $errors } ) )
    {
        $c->stash->{ errors } = $errors;

        map { $_ =~ s/Caught exception.*"(.*)at \/.*/$1/ } @{ $c->stash->{ errors } };

        my $message = 'Error(s): ' . join( '; ', @{ $c->stash->{ errors } } );
        my $body = MediaWords::Util::ParseJSON::encode_json( { 'error' => $message } );

        if ( $c->response->status =~ /^[23]\d\d$/ )
        {
            # Action roles and other parts might have set the HTTP status to
            # some other error value. In that case, do not touch it. If not,
            # default to 500 Internal Server Error
            $c->response->status( HTTP_INTERNAL_SERVER_ERROR );
        }
        $c->response->content_type( 'application/json; charset=UTF-8' );
        $c->response->body( $body );

        $c->clear_errors;
        $c->detach();
    }
    elsif ( $c->stash->{ quit_after_auth } )
    {
        my $body = MediaWords::Util::ParseJSON::encode_json( { 'success' => 1 } );

        $c->response->content_type( 'application/json; charset=UTF-8' );
        $c->response->body( $body );

        $c->detach();
    }
    else
    {
        $c->forward( 'serialize' );
    }
}

# throw an error if the given fields are not in the given data hash
sub require_fields ($$)
{
    my ( $self, $c, $fields ) = @_;

    my $data = $c->req->data;

    for my $field ( @{ $fields } )
    {
        if ( !exists( $data->{ $field } ) )
        {
            $c->response->status( HTTP_BAD_REQUEST );
            die( "Required field '$field' is not present" );
        }
    }
}

# update the given fields in the given table at the given id, pulling the update table from $c->req->data
sub update_table ($$$$$)
{
    my ( $self, $c, $table, $id, $fields ) = @_;

    my $db = $c->dbis;

    my $object = $db->require_by_id( $table, $id );

    my $data = {};
    for my $field ( @{ $fields } )
    {
        $data->{ $field } = $c->req->data->{ $field };
        $data->{ $field } //= $object->{ $field };
    }

    $db->update_by_id( $table, $id, $data );

    return $db->find_by_id( $table, $id );
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
