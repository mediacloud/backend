#!/usr/bin/env perl
#
# Test stateful Perl worker which doesn't even run
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;


sub main()
{
    INFO "Starting 'queued' Perl worker...";

    # Sleep indefinitely to keep the job in "queued" state
    while ( 1 ) {
        sleep( 10 );
    }
}

main();
