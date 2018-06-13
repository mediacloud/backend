package MediaWords::DBI::Auth::User::CurrentUser::Role;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub new
{
    my ( $class, %args ) = @_;

    my $self = {};
    bless $self, $class;

    unless ( $args{ python_object } )
    {
        LOGCONFESS "Python role object is not set.";
    }

    $self->{ _python_object } = $args{ python_object };

    return $self;
}

sub role_id($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->role_id();
}

sub role($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->role();
}

1;
