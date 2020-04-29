#!/usr/bin/env perl

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;


sub main()
{
    MediaWords::TM::Worker::start_topics_mine_worker( 'MediaWords::Job::TM::MineTopic' );
}

main();
