#!/usr/bin/env perl

#
# Enqueue MediaWords::GearmanFunction::CM::DumpControversy job
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
use MediaWords::CM::Dump;
use MediaWords::DB;
use MediaWords::CM;
use MediaWords::GearmanFunction;
use MediaWords::GearmanFunction::CM::DumpControversy;
use Gearman::JobScheduler;

sub main
{
    my ( $controversy_opt, $direct_job );

    unless ( MediaWords::GearmanFunction::gearman_is_enabled() )
    {
        die "Gearman is disabled.";
    }

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    Getopt::Long::GetOptions(
        "controversy=s" => \$controversy_opt,
        "direct_job!"   => \$direct_job
    ) || return;

    die( "Usage: $0 --controversy < id >" ) unless ( $controversy_opt );

    my $db = MediaWords::DB::connect_to_db();
    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );
    unless ( $controversies )
    {
        die "Unable to find controversies for option '$controversy_opt'";
    }

    for my $controversy ( @{ $controversies } )
    {
        if ( $direct_job )
        {
            MediaWords::CM::Dump::dump_controversy( $db, $controversy->{ controversies_id } );
            next;
        }

        my $args = { controversies_id => $controversy->{ controversies_id } };
        my $gearman_job_id = MediaWords::GearmanFunction::CM::DumpControversy->enqueue_on_gearman( $args );
        say STDERR
"Enqueued controversy ID $controversy->{ controversies_id } ('$controversy->{ name }') on Gearman with job ID: $gearman_job_id";

        # The following call might fail if the job takes some time to start,
        # so consider adding:
        #     sleep(1);
        # before calling log_path_for_gearman_job()
        my $log_path =
          Gearman::JobScheduler::log_path_for_gearman_job( MediaWords::GearmanFunction::CM::DumpControversy->name(),
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

__END__
