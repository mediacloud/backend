package MediaWords::DBI::Auth::User::NewOrModifyUser;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::User::AbstractUser;
our @ISA = qw(MediaWords::DBI::Auth::User::AbstractUser);

sub role_ids($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->role_ids();
}

sub password($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->password();
}

sub password_repeat($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->password_repeat();
}

1;
