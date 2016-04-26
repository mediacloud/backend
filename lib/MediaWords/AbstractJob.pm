package MediaWords::AbstractJob;

#
# Superclass of all Media Cloud jobs
#

use strict;
use warnings;

use Moose::Role;
with 'Gearman::JobScheduler::AbstractFunction';

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::Util::Config;
use Gearman::JobScheduler;
use MediaWords::Util::GearmanJobSchedulerConfiguration;

# (Gearman::JobScheduler::AbstractFunction implementation) Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    die "This is a placeholder implementation of the run() subroutine for the Gearman function.";
}

# (Gearman::JobScheduler::AbstractFunction implementation) Return default configuration
sub configuration()
{
    # It would be great to place configuration() in some sort of a superclass
    # for all the Media Cloud Gearman functions, but Moose::Role doesn't
    # support that :(
    return MediaWords::Util::GearmanJobSchedulerConfiguration->instance;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
