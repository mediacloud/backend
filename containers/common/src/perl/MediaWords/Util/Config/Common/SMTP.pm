package MediaWords::Util::Config::Common::SMTP;

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

sub use_starttls()
{
    return $self->{ _proxy_config }->use_starttls();
}

sub username()
{
    return $self->{ _proxy_config }->username();
}

sub password()
{
    return $self->{ _proxy_config }->password();
}

1;
