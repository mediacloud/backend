package MediaWords::Util::Config::Common::Database;

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

sub database_name()
{
    return $self->{ _proxy_config }->database_name();
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
