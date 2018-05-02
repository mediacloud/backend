package MediaWords::DBI::Auth::User::CurrentUser;

#
# User object for user returned by user_info()
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
extends 'MediaWords::DBI::Auth::User::AbstractUser';

use DateTime;

use MediaWords::DBI::Auth::User::CurrentUser::APIKey;
use MediaWords::DBI::Auth::User::CurrentUser::Role;

has 'id'                         => ( is => 'rw', isa => 'Int' );
has 'password_hash'              => ( is => 'rw', isa => 'Str' );
has 'api_keys'                   => ( is => 'rw', isa => 'ArrayRef[MediaWords::DBI::Auth::User::CurrentUser::APIKey]' );
has 'roles'                      => ( is => 'rw', isa => 'ArrayRef[MediaWords::DBI::Auth::User::CurrentUser::Role]' );
has 'created_timestamp'          => ( is => 'rw', isa => 'Int' );
has 'weekly_requests_sum'        => ( is => 'rw', isa => 'Int' );
has 'weekly_requested_items_sum' => ( is => 'rw', isa => 'Int' );

# Set by constructor
has 'global_api_key' => ( is => 'rw', isa => 'Str' );

has '_ip_addresses_to_api_keys' => ( is => 'rw', isa => 'HashRef[Str]' );
has '_roles_to_role_ids'        => ( is => 'rw', isa => 'HashRef[Int]' );

sub BUILD
{
    my $self = shift;

    unless ( $self->id() )
    {
        LOGCONFESS "User's ID is unset.";
    }
    unless ( $self->full_name() )
    {
        LOGCONFESS "User's full name is unset.";
    }
    unless ( defined $self->notes() )
    {
        LOGCONFESS "User's notes are undefined (should be at least an empty string).";
    }
    unless ( defined $self->created_timestamp() )
    {
        LOGCONFESS "User's creation timestamp is undefined.";
    }
    unless ( ref $self->roles() eq ref( [] ) )
    {
        LOGCONFESS "List of roles is not an arrayref: " . Dumper( $self->roles() );
    }
    unless ( defined $self->active() )
    {
        LOGCONFESS "'User is active' flag is unset.";
    }
    unless ( $self->password_hash() )
    {
        LOGCONFESS "Password hash is unset.";
    }
    unless ( ref $self->api_keys() eq ref( [] ) )
    {
        LOGCONFESS "List of API keys is not an arrayref: " . Dumper( $self->api_keys() );
    }
    unless ( defined $self->weekly_requests_sum() )
    {
        LOGCONFESS "Weekly requests sum is undefined.";
    }
    unless ( defined $self->weekly_requested_items_sum() )
    {
        LOGCONFESS "Weekly requested items sum is undefined.";
    }
    unless ( defined $self->weekly_requests_limit() )
    {
        LOGCONFESS "Weekly requests limit is undefined.";
    }
    unless ( defined $self->weekly_requested_items_limit() )
    {
        LOGCONFESS "Weekly requested items limit is undefined.";
    }

    $self->_ip_addresses_to_api_keys( {} );
    foreach my $api_key_obj ( @{ $self->api_keys() } )
    {
        my $api_key    = $api_key_obj->api_key();
        my $ip_address = $api_key_obj->ip_address();

        if ( defined $ip_address )
        {
            $self->_ip_addresses_to_api_keys()->{ $ip_address } = $api_key;
        }
        else
        {
            $self->global_api_key( $api_key );
        }

    }

    $self->_roles_to_role_ids( {} );
    foreach my $role_obj ( @{ $self->roles() } )
    {
        my $role_id = $role_obj->id();
        my $role    = $role_obj->role();
        $self->_roles_to_role_ids()->{ $role } = $role_id;
    }
}

sub api_key_for_ip_address($$)
{
    my ( $self, $ip_address ) = @_;

    return $self->_ip_addresses_to_api_keys()->{ $ip_address };
}

# User's creation date (ISO 8601 format)
sub created_date($)
{
    my ( $self ) = @_;

    return DateTime->from_epoch( epoch => $self->created_timestamp() )->iso8601();
}

# Tests whether role is enabled for user
sub has_role($$)
{
    my ( $self, $role ) = @_;

    return defined $self->_roles_to_role_ids()->{ $role };
}

# Shorthand for getting an arrayref of role names
sub role_names($)
{
    my ( $self ) = @_;

    return [ map { $_->role() } @{ $self->roles() } ];
}

no Moose;    # gets rid of scaffolding

1;
