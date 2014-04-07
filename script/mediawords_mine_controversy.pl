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
    my ( $controversies_id, $import_only, $cache_broken_downloads, $direct_job );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions(
        "controversy=s"           => \$controversies_id,
        "import_only!"            => \$import_only,
        "cache_broken_downloads!" => \$cache_broken_downloads,
        "direct_job!"             => \$direct_job,
    ) || return;

    my $optional_args = join( ' ', map { "[ --$_ ]" } qw(direct_job import_only cache_broken_downloads) );
    die( "usage: $0 --controversy < controversies_id > $optional_args" ) unless ( $controversies_id );

    if ( $direct_job )
    {
        my $db = MediaWords::DB::connect_to_db;

        my $controversy = $db->find_by_id( 'controversies', $controversies_id )
          or die( "Unable to find controversy '$controversies_id'" );

        my $options = {
            import_only            => $import_only,
            cache_broken_downloads => $cache_broken_downloads
        };

        MediaWords::CM::Mine::mine_controversy( $db, $controversy, $options );
    }
    else
    {
        my $args = {
            controversies_id       => $controversies_id,
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
}

main();
