#!/usr/bin/env perl

#
# Enqueue MediaWords::GearmanFunction::AddDefaultFeeds job
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2012";
use MediaWords::CommonLibs;
use MediaWords::GearmanFunction;

sub main
{
    unless ( MediaWords::GearmanFunction::gearman_is_enabled() )
    {
        die "Gearman is disabled.";
    }

    while ( 1 )
    {
        MediaWords::DBI::Media::enqueue_add_default_feeds_for_unmoderated_media();
        sleep( 60 );
    }
}

main();
