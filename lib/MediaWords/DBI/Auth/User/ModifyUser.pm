package MediaWords::DBI::Auth::User::ModifyUser;

#
# User object for user to be modified by update_user()
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
extends 'MediaWords::DBI::Auth::User::NewOrModifyUser';

sub BUILD
{
    my $self = shift;

    # Don't require anything but email to be set -- if undef, values won't be changed

    if ( defined( $self->role_ids() ) )
    {
        unless ( ref $self->role_ids() eq ref( [] ) )
        {
            LOGCONFESS "List of role IDs is not an array: " . Dumper( $self->role_ids() );
        }
    }

}

no Moose;    # gets rid of scaffolding

1;
