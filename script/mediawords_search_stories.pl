#!/usr/bin/env perl

#
# Enqueue MediaWords::GearmanFunction::SearchStories job
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2012";
use MediaWords::CommonLibs;
use MediaWords::GearmanFunction::SearchStories;
use Gearman::JobScheduler;
use MediaWords::DB;

sub main
{
    while ( 1 )
    {
        my $db = MediaWords::DB::connect_to_db();

        my $query_story_searches =
          $db->query( "SELECT query_story_searches_id FROM query_story_searches WHERE search_completed = 'f'" )->hashes;
        if ( scalar @{ $query_story_searches } )
        {
            # Enqueue one Gearman job for every story search query
            foreach my $query_story_search ( @{ $query_story_searches } )
            {
                my $query_story_searches_id = $query_story_search->{ query_story_searches_id };
                my $args = { query_story_searches_id => $query_story_searches_id };

                my $gearman_job_id = MediaWords::GearmanFunction::SearchStories->enqueue_on_gearman( $args );
                say STDERR "Enqueued story search query '$query_story_searches_id' with Gearman job ID: $gearman_job_id";

                # The following call might fail if the job takes some time to start,
                # so consider adding:
                #     sleep(1);
                # before calling log_path_for_gearman_job()
                my $log_path =
                  Gearman::JobScheduler::log_path_for_gearman_job( MediaWords::GearmanFunction::SearchStories->name(),
                    $gearman_job_id );
                if ( $log_path )
                {
                    say STDERR "The job is writing its log to: $log_path";
                }
                else
                {
                    say STDERR "The job probably hasn't started yet, so I don't know where does the log reside";
                }
            }
        }

        sleep( 60 );
    }
}

main();
