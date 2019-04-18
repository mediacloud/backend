package MediaWords::Util::Config::Common::AmazonS3Downloads;

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

sub access_key_id($)
{
    my $self = shift;
    return $self->{ _proxy_config }->access_key_id();
}

sub secret_access_key($)
{
    my $self = shift;
    return $self->{ _proxy_config }->secret_access_key();
}

sub bucket_name($)
{
    my $self = shift;
    return $self->{ _proxy_config }->bucket_name();
}

sub directory_name($)
{
    my $self = shift;
    return $self->{ _proxy_config }->directory_name();
}

1;
