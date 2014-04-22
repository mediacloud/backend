package MediaWords::Controller::Api::V2::MC_Action_REST;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;
use MediaWords::DBI::Auth;
use MediaWords::Controller::Api::V2::MC_Action_REST;

use strict;
use warnings;
use base 'Catalyst::Controller';
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;
use MediaWords::Util::Config;

=head1 NAME

MediaWords::Controller::Api::V2::MC_Controller_REST

=head1 DESCRIPTION

Light wrapper class over Catalyst::Controller::REST

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'Catalyst::Action::REST' }

sub execute
{
    my $self = shift;
    my ( $controller, $c, @args ) = @_;

    #say STDERR "before code";

    my $allow_unauth = MediaWords::Util::Config::get_config->{ mediawords }->{ allow_unauthenticated_api_requests } || 'no';
    if ( $allow_unauth ne 'yes' )
    {
        return unless $self->_valid_api_key( $c );
    }

    my $r = $self->next::method( @_ );

    #say STDERR "after code";
    # put your 'after' code here
    return $r;
}

sub _valid_api_key
{
    my ( $self, $c ) = @_;

    my $api_auth = MediaWords::DBI::Auth::user_for_api_token_catalyst( $c );

    if ( !$api_auth )
    {

        say STDERR "invalid key";

        my $controller = $c->component( $self->class );

        my $code = $controller->action_for( 'invalid_key' );

        $c->forward( $code, $c->request->args );

        $c->detach();

        return 0;
    }

    $c->stash->{ auth_user } = $api_auth;

    return $api_auth;
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
