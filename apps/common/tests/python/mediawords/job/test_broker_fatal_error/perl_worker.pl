#!/usr/bin/env perl
#
# Worker that fails pretty much right away.
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Job::Broker;
use MediaWords::Util::Process;


sub run_job($)
{
    my $args = shift;

    # Start some background processes to see if they get killed properly
    unless ( fork() ) {
        setpgrp();
        system( 'sleep 30' );
        exit( 0 );
    }
    unless ( fork() ) {
        setpgrp();
        system( 'sleep 30' );
        exit( 0 );
    }

    # Wait for the children processes to fire up
    sleep( 1 );

    MediaWords::Util::Process::fatal_error( 'Failing worker' );
}

sub main()
{
    my $app = MediaWords::Job::Broker->new( 'TestPerlWorkerFatalError' );
    $app->start_worker( \&run_job );
}

main();
