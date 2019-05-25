#!/usr/bin/env perl

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::JobManager::Worker;

MediaWords::JobManager::Worker::start_worker( 'MediaWords::Job::TM::MineTopic' );
