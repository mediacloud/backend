package MediaWords::DBI::Auth::User::NewUser;

#
# User object
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
extends 'MediaWords::DBI::Auth::User::AbstractUser';

use MediaWords::DBI::Auth::Password;

has 'password'        => ( is => 'rw', isa => 'Str' );
has 'password_repeat' => ( is => 'rw', isa => 'Str' );
has 'activation_url'  => ( is => 'rw', isa => 'Str' );

sub BUILD
{
    my $self = shift;

    unless ( $self->password() )
    {
        LOGCONFESS "Password is unset.";
    }
    unless ( $self->password_repeat() )
    {
        LOGCONFESS "Password repeat is unset.";
    }

    my $password_validation_message = MediaWords::DBI::Auth::Password::validate_new_password(
        $self->email(),             #
        $self->password(),          #
        $self->password_repeat()    #
    );
    if ( $password_validation_message )
    {
        LOGCONFESS "Password is invalid: $password_validation_message";
    }

    # Either activate the user right away, or make it inactive and send out an email with activation link
    if ( ( $self->active() and $self->activation_url() ) or ( ( !$self->active() ) and ( !$self->activation_url() ) ) )
    {
        LOGCONFESS "Either make the user active or set the activation URL.";
    }
}

no Moose;    # gets rid of scaffolding

1;
