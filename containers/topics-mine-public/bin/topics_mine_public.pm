#!mjm_worker.pl

package MediaWords::Job::TM::MineTopicPublic;

#
# This job is a copy of MineTopic but is used to run a separate job queue for topics requested by public users.

use strict;
use warnings;

use Moose;

extends 'MediaWords::Job::TM::MineTopic';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
