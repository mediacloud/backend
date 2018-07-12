package MediaWords::DBI::Auth::User::CurrentUser::APIKey;

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
        LOGCONFESS "Python API key object is not set.";
    }

    $self->{ _python_object } = $args{ python_object };

    return $self;
}

sub api_key($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->api_key();
}

sub ip_address($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->ip_address();
}

1;
