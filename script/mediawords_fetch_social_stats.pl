#!/usr/bin/env perl
#
# fetch facebook statistics for all stories in a topic
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

use Getopt::Long;

use MediaWords::DB;
use MediaWords::CM;
use MediaWords::Job::Facebook::FetchStoryStats;

# fetch stats from facebook for a single story
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
            eval( "MediaWords::Job::${ type }::FetchStoryStats->run_locally( \$args );" );
            if ( $@ )
            {
                say STDERR "Worker died while fetching and storing $stories_id: $@";
            }
        }
        else
        {
            say STDERR "Adding job for story $stories_id...";
            eval( "MediaWords::Job::${ type }::FetchStoryStats->add_to_queue( \$args )" );
            if ( $@ )
            {
                say STDERR "error queueing story $stories_id: $@";
            }
        }
    }
}

sub main
{
    my ( $topic_opt, $direct_job, $overwrite );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    Readonly my $usage => <<EOF;
Usage: $0 --topic < id > [--direct_job] [--overwrite]
EOF

    Getopt::Long::GetOptions(
        "topic=s"     => \$topic_opt,
        "direct_job!" => \$direct_job,
        "overwrite!"  => \$overwrite,
    ) or die $usage;
    die $usage unless ( $topic_opt );

    my $db = MediaWords::DB::connect_to_db;
    my $topics = MediaWords::CM::require_topics_by_opt( $db, $topic_opt );
    unless ( $topics )
    {
        die "Unable to find topics for option '$topic_opt'";
    }

    for my $topic ( @{ $topics } )
    {
        my $topics_id = $topic->{ topics_id };

        my $stories = $db->query( <<END, $topics_id )->hashes;
SELECT cs.stories_id cs_stories_id, ss.*
    FROM topic_stories cs
        left join story_statistics ss on ( ss.stories_id = cs.stories_id )
    WHERE topics_id = ?
END

        # ugly hack to disambiguate between cs.stories_id and ss.stories_id.  ss.stories_id may be null
        # because of the left join.
        map { $_->{ stories_id } = $_->{ cs_stories_id } } @{ $stories };

        unless ( scalar @{ $stories } )
        {
            say STDERR "No unprocessed stories found for topic '$topic->{ name }' ('$topic_opt')";
        }

        for my $story ( @{ $stories } )
        {
            fetch_stats( $story, 'Facebook', $overwrite, $direct_job );
        }
    }
}

main();
