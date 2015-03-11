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

    my $stories_ids = $db->query( "select stories_id from scratch.reextract_stories order by stories_id" )->flat;

    $db->dbh->{ AutoCommit } = 0;

    my $i = 0;
    for my $stories_id ( @{ $stories_ids } )
    {
        MediaWords::GearmanFunction::ExtractAndVector->run_locally(
            { stories_id => $stories_id, disable_story_triggers => 1 } );

        #$db->query( "delete from scratch.reextract_stories where stories_id = ?", $stories_id );
        if ( !( ++$i % 100 ) )
        {
            $db->commit;
            print STDERR "[$i]\n";
        }
    }

    $db->commit;
}

main();
