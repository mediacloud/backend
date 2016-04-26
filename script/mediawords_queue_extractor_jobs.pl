#!/usr/bin/env perl

#
# Add MediaWords::Job::ExtractAndVector job for every download in the scratch.reextract_downloads table
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
use MediaWords::Job::ExtractAndVector;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $downloads_ids = $db->query( "select downloads_id from scratch.reextract_downloads" )->flat;

    $db->dbh->{ AutoCommit } = 0;

    my $i = 0;
    for my $downloads_id ( @{ $downloads_ids } )
    {
        MediaWords::Job::ExtractAndVector->add_to_queue( { downloads_id => $downloads_id } );
        $db->query( "delete from scratch.reextract_downloads where downloads_id = ?", $downloads_id );
        if ( !( ++$i % 100 ) )
        {
            $db->commit;
            print STDERR "[$i]\n";
        }
    }

    $db->commit;
}

main();
