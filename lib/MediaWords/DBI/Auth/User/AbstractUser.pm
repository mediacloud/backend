package MediaWords::DBI::Auth::User::AbstractUser;

#
# User object
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;

has 'email'                        => ( is => 'rw', isa => 'Str' );
has 'full_name'                    => ( is => 'rw', isa => 'Str' );
has 'notes'                        => ( is => 'rw', isa => 'Str' );
has 'role_ids'                     => ( is => 'rw', isa => 'ArrayRef[Int]' );
has 'active'                       => ( is => 'rw', isa => 'Int' );             # boolean
has 'weekly_requests_limit'        => ( is => 'rw', isa => 'Int' );
has 'weekly_requested_items_limit' => ( is => 'rw', isa => 'Int' );

sub BUILD
{
    my $self = shift;

    unless ( $self->email() )
    {
        LOGCONFESS "User email is unset.";
    }
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
}

no Moose;    # gets rid of scaffolding

1;
