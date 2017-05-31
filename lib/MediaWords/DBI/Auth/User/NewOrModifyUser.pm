package MediaWords::DBI::Auth::User::NewOrModifyUser;

#
# New or existing user object
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
extends 'MediaWords::DBI::Auth::User::AbstractUser';

use MediaWords::DBI::Auth::Password;

has 'role_ids'                     => ( is => 'rw', isa => 'Maybe[ArrayRef[Int]]' );
has 'password'        => ( is => 'rw', isa => 'Maybe[Str]' );
has 'password_repeat' => ( is => 'rw', isa => 'Maybe[Str]' );

sub BUILD
{
    my $self = shift;

    if ( $self->password() and $self->password_repeat() )
    {
        my $password_validation_message = MediaWords::DBI::Auth::Password::validate_new_password(
            $self->email(),             #
            $self->password(),          #
            $self->password_repeat()    #
        );
        if ( $password_validation_message )
        {
            LOGCONFESS "Password is invalid: $password_validation_message";
        }
    }
}

no Moose;                               # gets rid of scaffolding

1;
