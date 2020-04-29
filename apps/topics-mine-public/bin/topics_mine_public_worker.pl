#!/usr/bin/env perl
#
# This job is a copy of MineTopic but is used to run a separate job queue for topics requested by public users.
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;


sub main()
{
    MediaWords::TM::Worker::start_topics_mine_worker( 'MediaWords::Job::TM::MineTopicPublic' );
}

main();
