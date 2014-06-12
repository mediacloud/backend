#!/usr/bin/env perl

#
# Enqueue MediaWords::GearmanFunction::ExtractAndVector jobs for all downloads
# in the scratch.reextract_downloads table
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";

use MediaWords::CommonLibs;
use MediaWords::GearmanFunction;
use MediaWords::GearmanFunction::ExtractAndVector;

sub main
{
    unless ( MediaWords::GearmanFunction::gearman_is_enabled() )
    {
        die "Gearman is disabled.";
    }

    my $db = MediaWords::DB::connect_to_db;

    my $downloads_ids = $db->query( "select downloads_id from scratch.reextract_downloads" )->hashes;

    for my $downloads_id ( @{ $downloads_ids } )
    {
        MediaWords::GearmanFunction::ExtractAndVector->enqueue_on_gearman( { downloads_id => $downloads_id } );
    }
}

main();
