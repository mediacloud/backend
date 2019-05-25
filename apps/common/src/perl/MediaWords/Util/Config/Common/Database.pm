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

sub hostname($)
{
    my $self = shift;
    return $self->{ _proxy_config }->hostname();
}

sub port($)
{
    my $self = shift;
    return $self->{ _proxy_config }->port();
}

sub database_name($)
{
    my $self = shift;
    return $self->{ _proxy_config }->database_name();
}

sub username($)
{
    my $self = shift;
    return $self->{ _proxy_config }->username();
}

sub password($)
{
    my $self = shift;
    return $self->{ _proxy_config }->password();
}

1;
