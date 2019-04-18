package MediaWords::Util::Config::Common::UserAgent;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::Util::Config::Common::UserAgent::AuthenticatedDomain;

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

sub blacklist_url_pattern($)
{
    my $self = shift;
    return $self->{ _proxy_config }->blacklist_url_pattern();
}

sub authenticated_domains($)
{
    my $self = shift;

    my $domains = [];
    for my $python_domain (@{ $self->{ _proxy_config }->authenticated_domains() }) {
        my $domain = MediaWords::Util::Config::Common::UserAgent::AuthenticatedDomain->new( $python_domain );
        push( @{ $domains }, $domain );
    }

    return $domains;
}

sub parallel_get_num_parallel($)
{
    my $self = shift;
    return $self->{ _proxy_config }->parallel_get_num_parallel();
}

sub parallel_get_timeout($)
{
    my $self = shift;
    return $self->{ _proxy_config }->parallel_get_timeout();
}

sub parallel_get_per_domain_timeout($)
{
    my $self = shift;
    return $self->{ _proxy_config }->parallel_get_per_domain_timeout();
}

sub throttled_domain_timeout($)
{
    my $self = shift;
    return $self->{ _proxy_config }->throttled_domain_timeout();
}

1;
