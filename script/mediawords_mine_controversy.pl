#!/usr/bin/env perl

#
# Enqueue MediaWords::GearmanFunction::CM::MineControversy job
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::CommonLibs;
use MediaWords::CM;
use MediaWords::GearmanFunction;
use MediaWords::GearmanFunction::CM::MineControversy;
use Gearman::JobScheduler;

sub main
{
    my ( $controversy_opt, $import_only, $cache_broken_downloads, $direct_job, $skip_outgoing_foreign_rss_links );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    $| = 1;

    unless ( MediaWords::GearmanFunction::gearman_is_enabled() )
    {
        die "Gearman is disabled.";
    }

    Getopt::Long::GetOptions(
        "controversy=s"                    => \$controversy_opt,
        "import_only!"                     => \$import_only,
        "cache_broken_downloads!"          => \$cache_broken_downloads,
        "direct_job!"                      => \$direct_job,
        "skip_outgoing_foreign_rss_links!" => \$skip_outgoing_foreign_rss_links,
    ) || return;

    my $optional_args =
      join( ' ', map { "[ --$_ ]" } qw(direct_job import_only cache_broken_downloads skip_outgoing_foreign_rss_links) );
    die( "usage: $0 --controversy < id > $optional_args" ) unless ( $controversy_opt );

    my $db = MediaWords::DB::connect_to_db;
    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );
    unless ( $controversies )
    {
        die "Unable to find controversies for option '$controversy_opt'";
    }

    for my $controversy ( @{ $controversies } )
    {
        my $controversies_id = $controversy->{ controversies_id };
        say STDERR "Processing controversy $controversies_id...";

        if ( $direct_job )
        {
            my $options = {
                import_only                     => $import_only,
                cache_broken_downloads          => $cache_broken_downloads,
                skip_outgoing_foreign_rss_links => $skip_outgoing_foreign_rss_links
            };

            MediaWords::CM::Mine::mine_controversy( $db, $controversy, $options );
        }
        else
        {
            my $args = {
                controversies_id                => $controversies_id,
                import_only                     => $import_only,
                cache_broken_downloads          => $cache_broken_downloads,
                skip_outgoing_foreign_rss_links => $skip_outgoing_foreign_rss_links
            };

            my $gearman_job_id = MediaWords::GearmanFunction::CM::MineControversy->enqueue_on_gearman( $args );
            say STDERR "Enqueued Gearman job with ID: $gearman_job_id";

            # The following call might fail if the job takes some time to start,
            # so consider adding:
            #     sleep(1);
            # before calling log_path_for_gearman_job()
            my $log_path =
              Gearman::JobScheduler::log_path_for_gearman_job( MediaWords::GearmanFunction::CM::MineControversy->name(),
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

        say STDERR "Done processing controversy $controversies_id.";
    }
}

main();
