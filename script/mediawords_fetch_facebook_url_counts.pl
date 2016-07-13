#!/usr/bin/env perl
#
# Fetch Facebook URL statistics for all stories in a topic
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

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    Readonly my $usage => <<EOF;
Usage: $0 --topic < id > [--direct_job] [--overwrite]
EOF

    my ( $topic_opt, $direct_job, $overwrite );
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
            SELECT ss.*, cs.stories_id
            FROM topic_stories cs left join story_statistics ss on ( cs.stories_id = ss.stories_id )
            WHERE cs.topics_id = ?
            ORDER BY cs.stories_id
END

        unless ( scalar @{ $stories } )
        {
            say STDERR "No stories found for topic '$topic->{ name }' ('$topic_opt')";
        }

        for my $ss ( @{ $stories } )
        {
            my $stories_id = $ss->{ stories_id };
            my $args = { stories_id => $stories_id };

            if (   $overwrite
                or $ss->{ facebook_api_error }
                or !defined( $ss->{ facebook_api_collect_date } )
                or !defined( $ss->{ facebook_share_count } )
                or !defined( $ss->{ facebook_comment_count } ) )
            {
                if ( $direct_job )
                {
                    say STDERR "Running local job for story $stories_id...";
                    eval { MediaWords::Job::Facebook::FetchStoryStats->run_locally( $args ); };
                    if ( $@ )
                    {
                        say STDERR "Worker died while fetching and storing statistics: $@";
                    }
                }
                else
                {
                    say STDERR "Adding job for story $stories_id...";
                    MediaWords::Job::Facebook::FetchStoryStats->add_to_queue( $args );
                }
            }
        }
    }
}

main();
