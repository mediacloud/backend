#!/usr/bin/env perl

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::TM::Worker;


sub main()
{
    MediaWords::TM::Worker::start_topics_mine_worker( 'MediaWords::Job::TM::MineTopic' );
}

main();
