package MediaWords::DBI::Auth::User::CurrentUser::APIKey;

#
# API key object
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;

has 'api_key'    => ( is => 'rw', isa => 'Str' );
has 'ip_address' => ( is => 'rw', isa => 'Maybe[Str]' );

sub BUILD
{
    my $self = shift;

    unless ( $self->api_key() )
    {
        LOGCONFESS "API key is unset.";
    }

    # IP address might be undef, which means that it's global API key
}

no Moose;    # gets rid of scaffolding

1;
