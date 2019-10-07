package MediaWords::Util::Config::Common::UserAgent::AuthenticatedDomain;

use strict;
use warnings;

use Modern::Perl "2015";

sub new($$)
{
    my ( $class, $proxy_domain ) = @_;

    my $self = {};
    bless $self, $class;

    unless ( $proxy_domain ) {
        die "Proxy domain object is unset.";
    }

    $self->{ _proxy_domain } = $proxy_domain;

    return $self;
}

sub domain($)
{
    my $self = shift;
    return $self->{ _proxy_domain }->domain();
}

sub username($)
{
    my $self = shift;
    return $self->{ _proxy_domain }->username();
}

sub password($)
{
    my $self = shift;
    return $self->{ _proxy_domain }->password();
}

1;
