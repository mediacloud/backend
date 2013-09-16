#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2012";
use MediaWords::CommonLibs;
use MediaWords::GearmanFunctions::SearchStories;

sub main
{
    while ( 1 )
    {
        MediaWords::GearmanFunctions::SearchStories->enqueue_on_gearman();
        sleep( 60 );
    }
}

main();
