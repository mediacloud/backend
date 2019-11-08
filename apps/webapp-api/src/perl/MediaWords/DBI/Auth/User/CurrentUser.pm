package MediaWords::DBI::Auth::User::CurrentUser;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::User::AbstractUser;
our @ISA = qw(MediaWords::DBI::Auth::User::AbstractUser);

use MediaWords::DBI::Auth::User::Resources;
use MediaWords::DBI::Auth::User::CurrentUser::APIKey;
use MediaWords::DBI::Auth::User::CurrentUser::Role;

sub user_id($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->user_id();
}

sub password_hash($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->password_hash();
}

sub api_keys($)
{
    my ( $self ) = @_;

    my $python_objects = $self->{ _python_object }->api_keys();

    my $perl_objects = [];

    foreach my $python_object ( @{ $python_objects } )
    {
        my $perl_object = MediaWords::DBI::Auth::User::CurrentUser::APIKey->new( python_object => $python_object, );
        push( @{ $perl_objects }, $perl_object );
    }

    return $perl_objects;
}

sub roles($)
{
    my ( $self ) = @_;

    my $python_objects = $self->{ _python_object }->roles();

    my $perl_objects = [];

    foreach my $python_object ( @{ $python_objects } )
    {
        my $perl_object = MediaWords::DBI::Auth::User::CurrentUser::Role->new( python_object => $python_object, );
        push( @{ $perl_objects }, $perl_object );
    }

    return $perl_objects;
}

sub created_timestamp($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->created_timestamp();
}

sub used_resources($)
{
    my ( $self ) = @_;

    return MediaWords::DBI::Auth::User::Resources->from_python_object( $self->{ _python_object }->used_resources() );
}

sub global_api_key($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->global_api_key();
}

sub api_key_for_ip_address($$)
{
    my ( $self, $ip_address ) = @_;

    return $self->{ _python_object }->api_key_for_ip_address( $ip_address );
}

sub created_date($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->created_date();
}

sub has_role($$)
{
    my ( $self, $role ) = @_;

    return int( $self->{ _python_object }->has_role( $role ) );
}

sub role_names($)
{
    my ( $self ) = @_;

    my @role_names = $self->{ _python_object }->role_names();

    return \@role_names;
}

1;
