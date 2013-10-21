#!/usr/bin/env perl

#
# Enqueue MediaWords::GearmanFunction::CM::MineControversy job
#

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::CommonLibs;
use MediaWords::GearmanFunction::CM::MineControversy;
use Gearman::JobScheduler;

sub main
{
    my ( $controversies_id, $dedup_stories, $import_only, $cache_broken_downloads );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions(
        "controversy=s"           => \$controversies_id,
        "dedup_stories!"          => \$dedup_stories,
        "import_only!"            => \$import_only,
        "cache_broken_downloads!" => \$cache_broken_downloads
    ) || return;

    die( "usage: $0 --controversy < controversies_id > [ --dedup_stories ] [ --import_only ] [ --cache_broken_downloads ]" )
      unless ( $controversies_id );

    my $args = {
        controversies_id       => $controversies_id,
        dedup_stories          => $dedup_stories,
        import_only            => $import_only,
        cache_broken_downloads => $cache_broken_downloads
    };
    my $gearman_job_id = MediaWords::GearmanFunction::CM::MineControversy->enqueue_on_gearman( $args );
    say STDERR "Enqueued Gearman job with ID: $gearman_job_id";

    # The following call might fail if the job takes some time to start,
    # so consider adding:
    #     sleep(1);
    # before calling log_path_for_gearman_job()
    my $log_path = Gearman::JobScheduler::log_path_for_gearman_job( MediaWords::GearmanFunction::CM::MineControversy->name(),
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

main();
