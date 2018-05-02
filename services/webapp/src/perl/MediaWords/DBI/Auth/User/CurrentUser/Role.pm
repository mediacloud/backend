package MediaWords::DBI::Auth::User::CurrentUser::Role;

#
# API key object
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;

has 'id'   => ( is => 'rw', isa => 'Int' );
has 'role' => ( is => 'rw', isa => 'Str' );

sub BUILD
{
    my $self = shift;

    unless ( $self->id() )
    {
        LOGCONFESS "Role ID is unset.";
    }
    unless ( $self->role() )
    {
        LOGCONFESS "Role is unset.";
    }
}

no Moose;    # gets rid of scaffolding

1;
