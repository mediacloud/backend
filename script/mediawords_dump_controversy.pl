#!/usr/bin/env perl

# Dump various controversy queries to csv and build a gexf file

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::CommonLibs;
use MediaWords::GearmanFunction::CM::DumpControversy;
use Gearman::JobScheduler;

sub main
{
    my ( $controversy_opt );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    Getopt::Long::GetOptions( "controversy=s" => \$controversy_opt ) || return;

    die( "Usage: $0 --controversy < id >" ) unless ( $controversy_opt );

    my $args = { controversy_opt => $controversy_opt };
    my $gearman_job_id = MediaWords::GearmanFunction::CM::DumpControversy->enqueue_on_gearman( $args );
    say STDERR "Enqueued Gearman job with ID: $gearman_job_id";

    eval {
        # The following call might fail if the job takes some time to start,
        # so consider adding:
        #     sleep(1);
        # before calling log_path_for_gearman_job()
        my $log_path =
          Gearman::JobScheduler::log_path_for_gearman_job( MediaWords::GearmanFunction::CM::DumpControversy->name(),
            $gearman_job_id );
        say STDERR "The job is writing its log to: $log_path";
    };
    if ( $@ )
    {
        say STDERR "The job probably hasn't started yet, so I don't know where does the log reside";
    }
}

main();

__END__
