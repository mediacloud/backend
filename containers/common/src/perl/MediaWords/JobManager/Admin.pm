
=head1 NAME

C<MediaWords::JobManager::Admin> - administration utilities.

=cut

package MediaWords::JobManager::Admin;

use strict;
use warnings;
use Modern::Perl "2012";

use MediaWords::JobManager;
use MediaWords::JobManager::Configuration;

sub show_jobs($)
{
    my $config = shift;

    unless ( $config )
    {
        die "Configuration is undefined.";
    }

    return $config->{ broker }->show_jobs();
}

sub cancel_job($$)
{
    my ( $config, $job_id ) = @_;

    unless ( $config )
    {
        die "Configuration is undefined.";
    }

    return $config->{ broker }->cancel_job( $job_id );
}

sub server_status($)
{
    my $config = shift;

    unless ( $config )
    {
        die "Configuration is undefined.";
    }

    return $config->{ broker }->server_status();
}

sub workers($)
{
    my $config = shift;

    unless ( $config )
    {
        die "Configuration is undefined.";
    }

    return $config->{ broker }->workers();
}

1;
