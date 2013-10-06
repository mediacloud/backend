#!/usr/bin/env perl

#
# Enqueue MediaWords::GearmanFunction::AddDefaultFeeds job
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
use MediaWords::GearmanFunction::AddDefaultFeeds;
use Gearman::JobScheduler;

sub main
{
    while ( 1 )
    {
        my $gearman_job_id = MediaWords::GearmanFunction::AddDefaultFeeds->enqueue_on_gearman();
        say STDERR "Enqueued Gearman job with ID: $gearman_job_id";

        eval {
            # The following call might fail if the job takes some time to start,
            # so consider adding:
            #     sleep(1);
            # before calling log_path_for_gearman_job()
            my $log_path =
              Gearman::JobScheduler::log_path_for_gearman_job( MediaWords::GearmanFunction::AddDefaultFeeds->name(),
                $gearman_job_id );
            say STDERR "The job is writing its log to: $log_path";
        };
        if ( $@ )
        {
            say STDERR "The job probably hasn't started yet, so I don't know where does the log reside";
        }

        sleep( 60 );
    }
}

main();
