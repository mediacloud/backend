package MediaWords::Job::TM::FetchTwitterUrls;

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Process;

sub run($;$)
{
    fatal_error( "Please run jobs of this kind using Python Celery worker." );
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
