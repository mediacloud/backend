#!/usr/bin/env perl
#
# fetch Twitter statistics for all stories in a controversy
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

use Getopt::Long;

use MediaWords::DB;
use MediaWords::CM;
use MediaWords::GearmanFunction;
use MediaWords::GearmanFunction::Twitter::FetchStoryStats;

sub main
{
    my ( $controversy_opt, $direct_job, $overwrite );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    Readonly my $usage => <<EOF;
Usage: $0 --controversy < id > [--direct_job] [--overwrite]
EOF

    Getopt::Long::GetOptions(
        "controversy=s" => \$controversy_opt,
        "direct_job!"   => \$direct_job,
        "overwrite!"    => \$overwrite,
    ) or die $usage;
    die $usage unless ( $controversy_opt );

    unless ( $direct_job )
    {
        unless ( MediaWords::GearmanFunction::gearman_is_enabled() )
        {
            die "Gearman is disabled.";
        }
    }

    my $db = MediaWords::DB::connect_to_db;
    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );
    unless ( $controversies )
    {
        die "Unable to find controversies for option '$controversy_opt'";
    }

    for my $controversy ( @{ $controversies } )
    {
        my $controversies_id = $controversy->{ controversies_id };

        my $stories = $db->query( <<END, $controversies_id )->hashes;
            SELECT stories_id
            FROM controversy_stories
            WHERE controversies_id = ?
            ORDER BY controversy_stories_id
END

        unless ( scalar @{ $stories } )
        {
            say STDERR "No stories found for controversy '$controversy->{ name }' ('$controversy_opt')";
        }

        for my $story ( @{ $stories } )
        {
            my $stories_id = $story->{ stories_id };
            my $args = { stories_id => $stories_id };

            my $ss = $db->query( "select * from story_statistics where stories_id = ?", $stories_id )->hash;

            if (   $overwrite
                or !$ss
                or $ss->{ twitter_url_tweet_count_error }
                or !defined( $ss->{ twitter_url_tweet_count } ) )
            {
                if ( $direct_job )
                {
                    say STDERR "Running local job for story $stories_id...";
                    eval { MediaWords::GearmanFunction::Twitter::FetchStoryStats->run_locally( $args ); };
                    if ( $@ )
                    {
                        say STDERR "Gearman worker died while fetching and storing statistics: $@";
                    }
                }
                else
                {
                    say STDERR "Enqueueing Gearman job for story $stories_id...";
                    MediaWords::GearmanFunction::Twitter::FetchStoryStats->enqueue_on_gearman( $args );
                }
            }
        }
    }
}

main();
