#!/usr/bin/env perl
#
# Bit.ly click distribution histogram
#
# Usage:
# ./script/run_with_carton.sh ./script/mediawords_bitly_click_distribution.pl [--limit 200] > histogram.csv
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
use MediaWords::Util::SQL;

use Getopt::Long;
use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $limit = 200;

    Readonly my $usage => <<"EOF";
Usage: $0 [--limit $limit]
EOF

    Getopt::Long::GetOptions( 'limit=i' => \$limit, ) or die $usage;

    my $db = MediaWords::DB::connect_to_db;

    say STDERR "Fetching (up to) $limit story IDs...";
    my $story_ids = $db->query(
        <<EOF,
        SELECT object_id AS stories_id
        FROM bitly_processing_results
        ORDER BY object_id
        LIMIT ?
EOF
        $limit
    )->flat;

    # CSV header
    say '"Hours since publish_date"';

    foreach my $stories_id ( @{ $story_ids } )
    {
        my $story = $db->find_by_id( 'stories', $stories_id );
        unless ( $story )
        {
            say STDERR "Unable to find story with ID $stories_id";
            next;
        }

        my $publish_date = $story->{ publish_date };
        unless ( $publish_date )
        {
            say STDERR "Publish date is unset for story $stories_id";
            next;
        }

        my $publish_timestamp = MediaWords::Util::SQL::get_epoch_from_sql_date( $publish_date );
        if ( $publish_timestamp < 1 )
        {
            say STDERR "Incorrect publish timestamp for story $stories_id";
            next;
        }

        my $story_stats = MediaWords::Util::Bitly::read_story_stats( $db, $stories_id );
        unless ( $story_stats )
        {
            die "Unable to fetch Bit.ly story stats for story $stories_id";
        }

        foreach my $bitly_hash ( keys %{ $story_stats->{ data } } )
        {
            foreach my $bitly_clicks ( @{ $story_stats->{ data }->{ $bitly_hash }->{ clicks } } )
            {
                foreach my $link_click ( @{ $bitly_clicks->{ link_clicks } } )
                {
                    my $clicks     = $link_click->{ clicks } + 0;
                    my $dt         = $link_click->{ dt } + 0;
                    my $diff       = $dt - $publish_timestamp;
                    my $diff_hours = int( $diff / 60 / 60 );

                    for ( my $x = 0 ; $x < $clicks ; ++$x )
                    {
                        say "$diff_hours";
                    }
                }
            }
        }
    }

    say STDERR "Done.";
}

main();
