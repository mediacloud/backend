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
use MediaWords::DBI::Stories;

sub main
{
    unless ( MediaWords::GearmanFunction::gearman_is_enabled() )
    {
        die "Gearman is disabled.";
    }

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    my $tags_id = MediaWords::DBI::Stories::get_current_extractor_version_tags_id( $db );

    my $last_processed_stories_id = 0;

    my $story_batch_size = 10;

    while ( 1 )
    {
        my $rows = $db->query(
"select ps.* from processed_stories ps where processed_stories_id > ? EXCEPT select ps.* from processed_stories ps, stories_tags_map stm where ps.stories_id = stm.stories_id AND processed_stories_id > ? AND tags_id = ? order by processed_stories_id asc limit ? ",
            $last_processed_stories_id, $last_processed_stories_id, $tags_id, $story_batch_size )->hashes;

        my $stories_ids = [ map { $_->{ stories_id } } @$rows ];

        last if scalar( @$stories_ids ) == 0;

        $last_processed_stories_id = $rows->[ -1 ]->{ processed_stories_id };

        my $i = 0;

        say Dumper( $stories_ids );

        for my $stories_id ( @{ $stories_ids } )
        {
            MediaWords::GearmanFunction::ExtractAndVector->enqueue_on_gearman(
                { stories_id => $stories_id, disable_story_triggers => 1 } );

            if ( !( ++$i % 100 ) )
            {
                $db->commit;
                print STDERR "[$i]\n";
            }
        }
    }
    $db->commit;
}

main();
