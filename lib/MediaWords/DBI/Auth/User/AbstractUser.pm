package MediaWords::DBI::Auth::User::AbstractUser;

#
# Abstract user object
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;

has 'email'                        => ( is => 'rw', isa => 'Str' );
has 'full_name'                    => ( is => 'rw', isa => 'Maybe[Str]' );
has 'notes'                        => ( is => 'rw', isa => 'Maybe[Str]' );
has 'active'                       => ( is => 'rw', isa => 'Maybe[Int]' );    # boolean
has 'weekly_requests_limit'        => ( is => 'rw', isa => 'Maybe[Int]' );
has 'weekly_requested_items_limit' => ( is => 'rw', isa => 'Maybe[Int]' );

sub BUILD
{
    my $self = shift;

    unless ( $self->email() )
    {
        LOGCONFESS "User email is unset.";
    }
}

no Moose;    # gets rid of scaffolding

1;
