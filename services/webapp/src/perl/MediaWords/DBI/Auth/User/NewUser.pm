package MediaWords::DBI::Auth::User::NewUser;

#
# User object for user to be created by add_user()
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
extends 'MediaWords::DBI::Auth::User::NewOrModifyUser';

has 'subscribe_to_newsletter' => ( is => 'rw', isa => 'Int' );
has 'activation_url'          => ( is => 'rw', isa => 'Str' );

sub BUILD
{
    my $self = shift;

    unless ( $self->full_name() )
    {
        LOGCONFESS "User full name is unset.";
    }
    unless ( defined $self->notes() )
    {
        LOGCONFESS "User notes are undefined (should be at least an empty string).";
    }
    unless ( ref $self->role_ids() eq ref( [] ) )
    {
        LOGCONFESS "List of role IDs is not an array: " . Dumper( $self->role_ids() );
    }
    unless ( $self->password() )
    {
        LOGCONFESS "Password is unset.";
    }
    unless ( $self->password_repeat() )
    {
        LOGCONFESS "Password repeat is unset.";
    }

    # Password will be verified by ::NewOrModifyUser

    # Either activate the user right away, or make it inactive and send out an email with activation link
    if ( ( $self->active() and $self->activation_url() ) or ( ( !$self->active() ) and ( !$self->activation_url() ) ) )
    {
        LOGCONFESS "Either make the user active or set the activation URL.";
    }
}

no Moose;    # gets rid of scaffolding

1;
