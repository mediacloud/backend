#!/usr/bin/env perl
#
# Benchmark CoreNLP server.
#
# Usage:
#
#     mediawords_benchmark_corenlp.pl random_story_count
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;
use MediaWords::Util::CoreNLP;
use MediaWords::Job::AnnotateWithCoreNLP;

use Parallel::Fork::BossWorkerAsync;
use Time::HiRes;

sub _random_corenlp_story_ids($$)
{
    my ( $db, $random_story_count ) = @_;

    # http://stackoverflow.com/a/8675160/200603
    my $story_ids = $db->query(
        <<'EOF',
        WITH params AS (
            SELECT MIN(stories_id) AS min_id,
                   MAX(stories_id) AS max_id,
                   MAX(stories_id) - MIN(stories_id) AS id_span
            FROM stories
        )
        SELECT random_stories_id
        FROM (
            SELECT p.min_id + TRUNC(RANDOM() * p.id_span)::integer AS random_stories_id
            
            -- story count + buffer
            FROM params p, GENERATE_SERIES(1, FLOOR($1 * 2.0)::integer) AS g

            -- trim duplicates
            GROUP BY 1
            ) r
        INNER JOIN stories ON stories.stories_id = random_stories_id
            AND ( stories.language = 'en' OR stories.language IS NULL )
            AND EXISTS (
                SELECT 1
                FROM media
                WHERE media.annotate_with_corenlp = 't'
                  AND media.media_id = stories.media_id
            )
            AND EXISTS (
                SELECT 1
                FROM story_sentences
                WHERE story_sentences.stories_id = stories.stories_id
            )

        -- trim surplus
        LIMIT $1
EOF
        $random_story_count
    )->flat;
    return $story_ids;
}

sub _benchmark_corenlp_annotation($)
{
    my $job = shift;

    my $stories_id = $job->{ stories_id };

    my $start = Time::HiRes::gettimeofday();
    MediaWords::Job::AnnotateWithCoreNLP->run_remotely( { stories_id => $stories_id } );
    my $end = Time::HiRes::gettimeofday();

    return { stories_id => $stories_id, elapsed => $end - $start };
}

sub main
{
    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    my $random_story_count = $ARGV[ 0 ];
    unless ( $random_story_count )
    {
        LOGDIE( "Usage: $0 random_story_count" );
    }

    my $db = MediaWords::DB::connect_to_db;

    my $worker_count = int( `ps ax | grep perl | grep AnnotateWithCoreNLP.pm | grep -v grep | wc -l | awk '{print \$1}'` );
    unless ( $worker_count )
    {
        LOGDIE( "Start one or more AnnotateWithCoreNLP workers before benchmarking!" );
    }
    INFO( "Worker count: $worker_count" );

    INFO( "Fetching ~$random_story_count random story IDs..." );
    my $story_ids = _random_corenlp_story_ids( $db, $random_story_count );
    my $story_count = scalar( @{ $story_ids } );
    INFO( "Fetched $story_count random story IDs" );

    my $bw = Parallel::Fork::BossWorkerAsync->new(
        work_handler => \&_benchmark_corenlp_annotation,

        # to keep all job broker workers busy for as long as possible
        worker_count => $worker_count,
    );

    INFO( "Adding stories to the queue..." );
    for my $stories_id ( @{ $story_ids } )
    {
        $bw->add_work( { stories_id => $stories_id } );
    }

    INFO( "Waiting for story jobs to complete..." );
    my $total_elapsed = 0;

    my $stories_annotated = 0;
    while ( $bw->pending() )
    {
        my $ref = $bw->get_result();
        if ( $ref->{ ERROR } )
        {
            LOGDIE( "Error while annotating story: " . $ref->{ ERROR } );
        }

        my $stories_id = $ref->{ stories_id };
        my $elapsed    = $ref->{ elapsed };

        ++$stories_annotated;
        $total_elapsed += $elapsed;

        INFO(
            sprintf(
                "Story %d / %d (stories_id = %d) annotated in: %.2f s, total elapsed time: %.2f s",
                $stories_annotated, $story_count, $stories_id, $elapsed, $total_elapsed
            )
        );
    }
    $bw->shut_down();

    unless ( $story_count == $stories_annotated )
    {
        LOGDIE( "Not all stories have been annotated (annotated: $stories_annotated; total: $story_count" );
    }

    INFO( "All stories have been annotated." );

    INFO(
        sprintf(
            "Workers: %d; stories: %d; total time: %.2f; time per story: %.2f",
            $worker_count, $story_count, $total_elapsed, $total_elapsed / $story_count
        )
    );
}

main();
