package MediaWords::Util::Config::Common::DownloadStorage;

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

sub storage_locations($)
{
    my $self = shift;
    return $self->{ _proxy_config }->storage_locations();
}

sub read_all_from_s3($)
{
    my $self = shift;
    return $self->{ _proxy_config }->read_all_from_s3();
}

sub fallback_postgresql_to_s3($)
{
    my $self = shift;
    return $self->{ _proxy_config }->fallback_postgresql_to_s3();
}

sub cache_s3($)
{
    my $self = shift;
    return $self->{ _proxy_config }->cache_s3();
}

1;
