#!/usr/bin/env perl

use strict;
use warnings;
use Modern::Perl "2012";

use FindBin;
use lib "$FindBin::Bin/../samples";

use Gearman::JobScheduler;
use Gearman::JobScheduler::Configuration;

use Gearman::XS qw(:constants);
use Gearman::XS::Worker;

use Parallel::ForkManager;

use Data::Dumper;

use constant PM_MAX_PROCESSES => 32;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init( { level => $DEBUG, utf8 => 1, layout => "%d{ISO8601} [%P]: %m%n" } );

use Getopt::Long qw(:config auto_help);
use Pod::Usage;

sub import_gearman_function($)
{
    my ( $path_or_name ) = shift;

    eval {
        if ( $path_or_name =~ /\.pm$/ )
        {
            # /somewhere/Foo/Bar.pm

            # Expect the package to return its name so that we'll know how to call it:
            # http://stackoverflow.com/a/9850017/200603
            $path_or_name = require $path_or_name;
            if ( $path_or_name . '' eq '1' )
            {
                LOGDIE( "The function package should return __PACKAGE__ at the end of the file instead of just 1." );
            }
            $path_or_name->import();
            1;
        }
        else
        {
            # Foo::Bar
            ( my $file = $path_or_name ) =~ s|::|/|g;
            require $file . '.pm';
            $path_or_name->import();
            1;
        }
    } or do
    {
        LOGDIE( "Unable to find Gearman function in '$path_or_name': $@" );
    };

    return $path_or_name;
}

sub run_worker($$)
{
    my ( $config, $gearman_function_name ) = @_;

    $gearman_function_name = import_gearman_function( $gearman_function_name );
    INFO( "Initializing with Gearman function '$gearman_function_name'." );

    my $ret;
    my $worker = new Gearman::XS::Worker;

    $ret = $worker->add_servers( join( ',', @{ $config->gearman_servers } ) );
    unless ( $ret == GEARMAN_SUCCESS )
    {
        LOGDIE( "Unable to add Gearman servers: " . $worker->error() );
    }

    INFO( "Job priority: " . $gearman_function_name->priority() );

    $ret = $worker->add_function(
        $gearman_function_name,
        $gearman_function_name->timeout() * 1000,    # in milliseconds
        sub {
            my ( $gearman_job ) = shift;

            my $job_handle = $gearman_job->handle();
            my $result;
            eval { $result = $gearman_function_name->_run_locally_from_gearman_worker( $config, $gearman_job ); };
            if ( $@ )
            {
                INFO( "Gearman job '$job_handle' died: $@" );
                $gearman_job->send_fail();
                return undef;
            }
            else
            {
                $gearman_job->send_complete( $result );
                return $result;
            }
        },
        0
    );
    unless ( $ret == GEARMAN_SUCCESS )
    {
        LOGDIE( "Unable to add Gearman function '$gearman_function_name': " . $worker->error() );
    }

    INFO( "Worker is ready and accepting jobs" );
    while ( 1 )
    {
        $ret = $worker->work();
        unless ( $ret == GEARMAN_SUCCESS )
        {
            LOGDIE( "Unable to execute Gearman job: " . $worker->error() );
        }
    }
}

sub run_all_workers($$)
{
    my ( $config, $gearman_functions_directory ) = @_;

    # Run all workers
    INFO( "Initializing with all functions from directory '$gearman_functions_directory'." );
    my @function_modules = glob $gearman_functions_directory . '/*.pm';
    if ( scalar @function_modules > PM_MAX_PROCESSES )
    {
        LOGDIE( "Too many workers to be started." );
    }

    my $pm = Parallel::ForkManager->new( PM_MAX_PROCESSES );

    foreach my $function_module ( @function_modules )
    {

        $pm->start( $function_module ) and next;    # do the fork

        run_worker( $config, $function_module );

        $pm->finish;                                # do the exit in the child process

    }

    INFO( "All workers ready." );
    $pm->wait_all_children;
}

sub main()
{
    # Initialize with default configuration (to be customized later)
    my $config = Gearman::JobScheduler::_default_configuration();

    # Override default configuration options from the command line if needed
    GetOptions(
        'server:s@'           => \$config->gearman_servers,
        'worker_log_dir:s'    => \$config->worker_log_dir,
        'notif_email:s@'      => \$config->notifications_emails,
        'notif_from:s'        => \$config->notifications_from_address,
        'notif_subj_prefix:s' => \$config->notifications_subject_prefix,
    );

    # Function name, path to function module or path to directory with all functions
    unless ( scalar( @ARGV ) == 1 )
    {
        pod2usage( 1 );
    }
    my $gearman_function_name_or_directory = $ARGV[ 0 ];

    INFO( "Will use Gearman servers: " . join( ' ', @{ $config->gearman_servers } ) );
    if ( scalar @{ $config->notifications_emails } )
    {
        INFO( 'Will send notifications about failed jobs to: ' . join( ' ', @{ $config->notifications_emails } ) );
        INFO( '(emails will be sent from "' .
              $config->notifications_from_address . '" and prefixed with "' . $config->notifications_subject_prefix . '")' );
    }
    else
    {
        INFO( 'Will not send notifications anywhere about failed jobs.' );
    }

    if ( -d $gearman_function_name_or_directory )
    {

        # Run all workers
        run_all_workers( $config, $gearman_function_name_or_directory );

    }
    else
    {

        # Run single worker
        run_worker( $config, $gearman_function_name_or_directory );
    }

}

main();

=head1 NAME

worker.pl - Start one or all GJS workers

=head1 SYNOPSIS

worker.pl [options] GearmanFunction

or:

worker.pl [options] path/to/GearmanFunction.pm

or:

worker.pl [options] path_to/dir_with/gearman_functions/


 Options:
	--server=host[:port]            use Gearman server at host[:port] (multiple allowed)
	--worker_log_dir=/path/to/logs  directory where worker logs should be stored
	--notif_email=jdoe@example.com  whom to send notification emails about failed jobs to (multiple allowed)
	--notif_from=gjs@example.com    sender of the notification emails about failed jobs
	--notif_subj_prefix="[GJS]"     prefix of the subject line of notification emails about failed jobs

=cut
