#!/usr/bin/env perl
#
# fetch facebook and twitter statistics for all stories in a controversy
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
use MediaWords::GearmanFunction::Twitter::FetchStoryURLStats;
use MediaWords::GearmanFunction::Facebook::FetchStoryURLStats;

# fetch stats from either twitter or facebook for a single story
sub fetch_stats
{
    my ( $story, $type, $overwrite, $direct_job ) = @_;

    my $stories_id = $story->{ stories_id };
    my $args = { stories_id => $stories_id };

    my $lc_type = lc( $type );

    if (   $overwrite
        or $story->{ "${ lc_type }_api_error" }
        or !defined( $story->{ "${ lc_type }_api_collect_date" } )
        or !defined( $story->{ "${ lc_type }_url_tweet_count" } ) )
    {

        if ( $direct_job )
        {
            say STDERR "Running local job for story $stories_id...";
            eval( "MediaWords::GearmanFunction::${ type }::FetchStoryURLStats->run_locally( \$args );" );
            if ( $@ )
            {
                say STDERR "Gearman worker died while fetching and storing $stories_id: $@";
            }
        }
        else
        {
            say STDERR "Enqueueing Gearman job for story $stories_id...";
            eval( "MediaWords::GearmanFunction::${ type }::FetchStoryURLStats->enqueue_on_gearman( \$args )" );
            if ( $@ )
            {
                say STDERR "error queueing story $stories_id: $@";
            }
        }
    }
}

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
SELECT cs.stories_id cs_stories_id, ss.*
    FROM controversy_stories cs
        left join story_statistics ss on ( ss.stories_id = cs.stories_id )
    WHERE controversies_id = ?
END

        # ugly hack to disambiguate between cs.stories_id and ss.stories_id.  ss.stories_id may be null
        # because of the left join.
        map { $_->{ stories_id } = $_->{ cs_stories_id } } @{ $stories };

        unless ( scalar @{ $stories } )
        {
            say STDERR "No unprocessed stories found for controversy '$controversy->{ name }' ('$controversy_opt')";
        }

        for my $story ( @{ $stories } )
        {
            fetch_stats( $story, 'Twitter',  $overwrite, $direct_job );
            fetch_stats( $story, 'Facebook', $overwrite, $direct_job );
        }
    }
}

main();
