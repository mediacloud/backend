#!/usr/bin/env perl

#
# Enqueue MediaWords::Job::RescrapeMedia job
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::AbstractJob;
use MediaWords::DBI::Media;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    while ( 1 )
    {
        MediaWords::DBI::Media::enqueue_add_default_feeds_for_unmoderated_media( $db );
        sleep( 60 );
    }
}

main();
