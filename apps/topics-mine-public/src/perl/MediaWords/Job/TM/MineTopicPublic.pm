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

1;
