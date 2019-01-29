package MediaWords::Util::Config::Common::RabbitMQ;

use strict;
use warnings;

use Modern::Perl "2015";

sub new($$)
{
    my ( $class, $proxy_config ) = @_;

    my $self = {};
    bless $self, $class;

    unless ( $proxy_config ) {
        die "Proxy configuration object is unset.";
    }

    $self->{ _proxy_config } = $proxy_config;

    return $self;
}

sub hostname()
{
    return $self->{ _proxy_config }->hostname();
}

sub port()
{
    return $self->{ _proxy_config }->port();
}

sub username()
{
    return $self->{ _proxy_config }->username();
}

sub password()
{
    return $self->{ _proxy_config }->password();
}

sub vhost()
{
    return $self->{ _proxy_config }->vhost();
}

sub timeout()
{
    return $self->{ _proxy_config }->timeout();
}

1;
