package MediaWords::Controller::Api::V2::MC_Controller_REST;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;
use MediaWords::DBI::Auth;

use strict;
use warnings;
use base 'Catalyst::Controller::REST';
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;
use HTTP::Status qw(:constants);

=head1 NAME

MediaWords::Controller::Api::V2::MC_Controller_REST

=head1 DESCRIPTION

Light wrapper class over Catalyst::Controller::REST

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    'default'   => 'application/json; charset=UTF-8',
    'stash_key' => 'rest',
    'map'       => {

        #	   'text/html'          => 'YAML::HTML',
        'text/xml' => 'XML::Simple',

        # #         'text/x-yaml'        => 'YAML',
        'application/json'                => 'JSON',
        'application/json; charset=UTF-8' => 'JSON',
        'text/x-json'                     => 'JSON',
        'text/x-data-dumper'              => [ 'Data::Serializer', 'Data::Dumper' ],
        'text/x-data-denter'              => [ 'Data::Serializer', 'Data::Denter' ],
        'text/x-data-taxi'                => [ 'Data::Serializer', 'Data::Taxi' ],
        'application/x-storable'          => [ 'Data::Serializer', 'Storable' ],
        'application/x-freezethaw'        => [ 'Data::Serializer', 'FreezeThaw' ],
        'text/x-config-general'           => [ 'Data::Serializer', 'Config::General' ],
        'text/x-php-serialization'        => [ 'Data::Serializer', 'PHP::Serialization' ],
    },
    json_options => { relaxed => 1, pretty => 1, space_before => 2, indent => 1, space_after => 2 }
);

__PACKAGE__->config( json_options => { relaxed => 1, pretty => 1, space_before => 2, indent => 1, space_after => 2 } );

sub serialize : ActionClass('Serialize')
{
    # Just calls parent
}

# Catch Catalyst exceptions (controller actions that have died); report them in
# JSON back to the client
sub end : Private
{
    my ( $self, $c ) = @_;

    if ( scalar @{ $c->error } )
    {
        $c->stash->{ errors } = $c->error;

        for my $error ( @{ $c->error } )
        {
            $c->log->error( $error );
        }

        my $message = 'Error(s): ' . join( '; ', @{ $c->stash->{ errors } } );
        my $body = JSON->new->utf8->encode( { 'error' => $message } );

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
    else
    {

        # Continue towards serializing JSON results
        # (http://search.cpan.org/~frew/Catalyst-Action-REST-1.15/lib/Catalyst/Controller/REST.pm#IMPLEMENTATION_DETAILS)
        $c->forward( 'serialize' );

    }
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
