#!/usr/bin/env perl
#
# Enqueue stories that have their Bit.ly stats fetched but not yet aggregated
#
# If you append "--overwrite" parameter, script will first remove story entries
# from "controversy_stories_bitly_statistics" table and then enqueue all controversy's
# stories for re-aggregation.
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
use MediaWords::DB;
use MediaWords::Util::Bitly;
use MediaWords::CM;
use MediaWords::GearmanFunction::Bitly::AggregateStoryStats;

use Getopt::Long;
use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Readonly my $usage => <<EOF;
Usage: $0 --controversy < controversy id or pattern > [--overwrite]
EOF

    my ( $controversy_opt, $overwrite );
    Getopt::Long::GetOptions(
        'controversy=s' => \$controversy_opt,
        'overwrite'     => \$overwrite
    ) or die $usage;

    die $usage unless ( $controversy_opt );

    my $db = MediaWords::DB::connect_to_db;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );

    for my $controversy ( @{ $controversies } )
    {
        my $controversies_id = $controversy->{ controversies_id };

        unless ( $controversy->{ process_with_bitly } )
        {
            say STDERR "Controversy $controversies_id is not set up for Bit.ly, skipping.";
            next;
        }

        if ( $overwrite )
        {
            say STDERR
"Not testing whether any controversy's $controversies_id stories are processed already because I will overwrite them anyway.";
        }
        else
        {
            if ( MediaWords::Util::Bitly::num_controversy_stories_without_bitly_statistics( $db, $controversies_id ) == 0 )
            {
                say STDERR "All controversy's $controversies_id stories are processed against Bit.ly, skipping.";
                next;
            }
        }

        my $stories_to_enqueue;
        if ( $overwrite )
        {
            $stories_to_enqueue = $db->query(
                <<EOF,
                SELECT stories_id
                FROM controversy_stories
                WHERE controversies_id = ?
                ORDER BY stories_id
EOF
                $controversies_id
            )->hashes;
        }
        else
        {
            $stories_to_enqueue = $db->query(
                <<EOF,
                SELECT stories_id
                FROM controversy_stories
                WHERE controversies_id = ?
                  AND stories_id NOT IN (
                    SELECT stories_id
                    FROM controversy_stories_bitly_statistics
                )
                ORDER BY stories_id
EOF
                $controversies_id
            )->hashes;
        }

        foreach my $story ( @{ $stories_to_enqueue } )
        {
            my $stories_id = $story->{ stories_id };

            unless ( MediaWords::Util::Bitly::story_stats_are_fetched( $db, $stories_id ) )
            {
                say STDERR "Story $stories_id has not been fetched yet.";
                next;
            }

            if ( $overwrite )
            {
                say STDERR
                  "Removing old aggregation result from 'controversy_stories_bitly_statistics' for story $stories_id...";
                $db->query(
                    <<EOF,
                    DELETE FROM controversy_stories_bitly_statistics
                    WHERE stories_id = ?
EOF
                    $stories_id
                );
            }

            say STDERR "Enqueueing story $stories_id...";
            MediaWords::GearmanFunction::Bitly::AggregateStoryStats->enqueue_on_gearman( { stories_id => $stories_id } );
        }
    }
}

main();
