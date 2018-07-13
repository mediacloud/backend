#!/usr/bin/env perl

# refresh the data in the mediacloud_stats table

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Stats;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    MediaWords::DBI::Stats::refresh_stats( $db );
}

main();
