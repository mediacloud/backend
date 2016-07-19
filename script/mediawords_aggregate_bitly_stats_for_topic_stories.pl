#!/usr/bin/env perl
#
# (Re-)aggregate Bit.ly stats for stories that have their Bit.ly stats fetched but not yet aggregated
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
use MediaWords::DB;
use MediaWords::Util::Bitly;
use MediaWords::TM;
use MediaWords::Job::Bitly::AggregateStoryStats;

use Getopt::Long;
use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Readonly my $usage => <<EOF;
Usage: $0 --topic < topic id or pattern >
EOF

    my ( $topic_opt );
    Getopt::Long::GetOptions( 'topic=s' => \$topic_opt, ) or die $usage;

    die $usage unless ( $topic_opt );

    my $db = MediaWords::DB::connect_to_db;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $topics = MediaWords::TM::require_topics_by_opt( $db, $topic_opt );

    for my $topic ( @{ $topics } )
    {
        my $topics_id = $topic->{ topics_id };

        if ( MediaWords::Util::Bitly::num_topic_stories_without_bitly_statistics( $db, $topics_id ) == 0 )
        {
            say STDERR "All topic's $topics_id stories are processed against Bit.ly, skipping.";
            next;
        }

        my $stories_to_add = $db->query(
            <<EOF,
            SELECT stories_id
            FROM topic_stories
            WHERE topics_id = ?
              AND stories_id NOT IN (
                SELECT stories_id
                FROM bitly_clicks_total
            )
            ORDER BY stories_id
EOF
            $topics_id
        )->hashes;

        foreach my $story ( @{ $stories_to_add } )
        {
            my $stories_id = $story->{ stories_id };

            unless ( MediaWords::Util::Bitly::story_stats_are_fetched( $db, $stories_id ) )
            {
                say STDERR "Story $stories_id has not been fetched yet.";
                next;
            }

            say STDERR "Addin story $stories_id...";
            MediaWords::Job::Bitly::AggregateStoryStats->add_to_queue( { stories_id => $stories_id } );
        }
    }
}

main();
