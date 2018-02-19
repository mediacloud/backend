package MediaWords::Test::Supervisor;

=head1 NAME

MediaWords::Test::Supervisor - functions for starting up supervisord processes for usse in tests

=head1 SYNOPSIS

    sub do_tests {
        my ( $db ) = @_;
        # do some tests
    }

    MediaWords::Test::Supervisor::test_with_superisor( \&do_tests, [ qw/solr_standalone extract_and_vector/ ] )
=head1 DESCRIPTION


This module handles starting and stopping supervisord processes for the sake of unit tests.

=cut

use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;

use MediaWords::Solr;
use MediaWords::Test::DB;
use MediaWords::Util::Paths;
use MediaWords::Util::Config;

# seconds to wait for solr to start accepting queries
Readonly my $SOLR_START_TIMEOUT => 90;

# seconds to wait for solr to complete install if solr log reports that it is installing
Readonly my $SOLR_INSTALL_TIMEOUT => 600;

# time to wait for a givne process to go from STARTING to RUNNING state
Readonly my $SOLR_RUN_TIMEOUT => 10;

# seconds to wait for supervisord to stop shutting down
Readonly my $SUPERVISOR_SHUTDOWN_TIMEOUT => 90;

# Seconds to wait for Supervisord / Supervisorctl to react
Readonly my $SUPERVISOR_COMMAND_TIMEOUT => 5;

# mediacloud root path and supervisor scripts
my $_mc_root_path      = MediaWords::Util::Paths::mc_root_path();
my $_supervisord_bin   = "$_mc_root_path/supervisor/supervisord.sh";
my $_supervisorctl_bin = "$_mc_root_path/supervisor/supervisorctl.sh";

# if there is a function for a given process in this hash, that function is called to verify
# that the process is ready for work (for instance that solr is ready for queries).  function should wait while polling
# if necessary until the process is ready (or die if there is an indication that the process is not ready)
my $_process_ready_functions = {
    'solr_standalone'     => \&_solr_standalone_ready,
    'job_broker:rabbitmq' => \&_rabbit_ready
};

# poll every second for $SOLR_START_TIMEOUT seconds.  return once an http request to solr succeeds.  die if the supervisor
# status is every anthing but RUNNING or if the $solr_timeout is reached.  If the solr_standalone log is downloading
# the solr distribution, go into a separate poll loop waiting for up to $SOLR_INSTALL_TIMEOUT for the solr install to
# finish.
sub _solr_standalone_ready($)
{
    my ( $db ) = @_;

    my $tail          = _run_supervisorctl( 'tail solr_standalone stderr' );
    my $is_installing = ( $tail =~ /Downloading Solr/ );

    my $solr_timeout = $is_installing ? $SOLR_INSTALL_TIMEOUT : $SOLR_START_TIMEOUT;
    while ( $solr_timeout-- > 0 )
    {
        my $status = _run_supervisorctl( 'status solr_standalone' );
        die( "bad solr status: '$status'" ) unless ( $status =~ /RUNNING/ );

        # try to execute a simple solr query; if no error is thrown, it worked and solr is up
        eval { MediaWords::Solr::query( $db, { q => '*:*', rows => 0 } ) };
        return unless ( $@ );

        sleep( $SUPERVISOR_COMMAND_TIMEOUT );
    }

    die( "solr failed to start after timeout" );
}

sub _rabbit_ready($)
{
    my ( $db ) = @_;

    my $rabbitmq_config = MediaWords::Util::Config::get_config->{ job_manager }->{ rabbitmq }->{ client };

    # creating a rabbitmq object automatically tries to connect to the server and has its own
    # timeout builtin, so all we have to do is make sure we can connect
    eval {
        MediaCloud::JobManager::Broker::RabbitMQ->new(
            hostname => $rabbitmq_config->{ hostname },    #
            port     => $rabbitmq_config->{ port },        #
            username => $rabbitmq_config->{ username },    #
            password => $rabbitmq_config->{ password },    #
            vhost    => $rabbitmq_config->{ vhost },       #
            timeout  => $rabbitmq_config->{ timeout },     #
            retries  => 120,                               # default of 60 might not be enough in limited EC2 environment
        );
    };
    die( "rabbitmq failed to start: '$@'" ) if ( $@ );
}

# run supervisorctl with the given string as the argument, return the stdout of the call
sub _run_supervisorctl($)
{
    my ( $arg ) = @_;

    my $output = `$_supervisorctl_bin $arg 2>&1`;

    return $output;
}

# run supervisord.  if supervisord is in the process of shutting down, keep trying to start it for
# $SUPERVISOR_SHUTDOWN_TIMEOUT seconds.  if it is running and not in the shut down process, die with an
# appropriate message
sub _run_supervisord()
{
    my $status;

    for my $i ( 1 .. $SUPERVISOR_SHUTDOWN_TIMEOUT )
    {
        my $command = '';

        # Make rabbitmq_wrapper.sh skip the 'ulimit -n' check because we might
        # be running on Travis / Vagrant / dev machine with such limit not
        # being increased
        $command .= "MC_SKIP_RABBIT_OPEN_FILES_LIMIT_CHECK=1 ";
        $command .= "$_supervisord_bin 2>&1";

        my $output = `$command`;
        unless ( $? )
        {
            # Succeeded
            return;
        }

        if ( $output =~ /Another program is already listening/ )
        {
            $status = _run_supervisorctl( 'status' );
            if ( !( $status =~ /SHUTDOWN_STATE/ ) )
            {
                DEBUG( "shutting down existing supervisord ..." );
                _run_supervisorctl( 'shutdown' );
            }

            # otherwise, supervisord is in the process of shutting down, so just wait
            DEBUG( "waiting for supervisord to finish shutting down ..." );
            sleep( $SUPERVISOR_COMMAND_TIMEOUT );
        }
    }

    if ( $status =~ /solr_standalone/ )
    {
        DEBUG( "timed out waiting for supervisord to finish shutting down.  proceeding with existing supervisord." );
    }
    else
    {
        LOGDIE( "unable to start supervisord" );
    }

    return;
}

# if any of the given processes are not running, start them.  die if any of the given processes are still not running.
sub _verify_processes_status($$)
{
    my ( $db, $processes ) = @_;

    # first send 'start' to all processes so that any stopped ones are starting in parallel
    map { _run_supervisorctl( "start $_" ) } @{ $processes };

    for my $process ( @{ $processes } )
    {
        my $process_is_running = 0;
        for my $i ( 1 .. $SOLR_RUN_TIMEOUT )
        {
            my $status = _run_supervisorctl( "status $process" );
            if ( $status =~ 'no such process' )
            {
                $status = _run_supervisorctl( "status $process:" );
            }

            my $process_re = qr/(\Q${process}\E|\Q${process}\E\:\Q${process}\E_\d\d)\s+([A-Z]+)/m;

            die( "no such process '$process'" ) unless ( $status =~ $process_re );
            my $state = $2;

            if ( $state eq 'RUNNING' )
            {
                $process_is_running = 1;
                last;
            }
            elsif ( ( $state eq 'STARTING' ) || ( $state eq 'BACKOFF' ) )
            {
                # just wait
            }
            elsif ( $state eq 'STOPPED' )
            {
                # might be a group or a single job, so just try both
                _run_supervisorctl( "start $process" );
                _run_supervisorctl( "start $process:" );
            }
            else
            {
                my $tail = _run_supervisorctl( "tail $process stderr" );
                chomp( $tail );
                die( "bad state for process '$process': $state [$tail]" );
            }

            DEBUG( "waiting for process $process which is in state '$state'" );
            sleep( $SUPERVISOR_COMMAND_TIMEOUT );
        }

        die( "$process not running" ) unless ( $process_is_running );
    }
}

# call $_process_ready_functions->{ $process } for each process, if it exists.
sub _verify_processes_ready($$)
{
    my ( $db, $processes ) = @_;

    for my $process ( @{ $processes } )
    {
        if ( my $func = $_process_ready_functions->{ $process } )
        {
            $func->( $db );
        }
    }
}

=head2 test_with_supervisor( $func [ , $start_processes ]  )

Start supervisord, verify that the given processes are running, run the given function using
MediaWords::Test::db::test_on_test_database, and then stop supervisord.  $func should accept a $db handle
pased in from test_on_test_database().

Will die if supervisord is already running, if supervisord does not start, or if any of the jobs cannot be started.

Supervisord will start in the default configuration (see docs/supervisord.markdown).

$start_processes should be a reference to an array of process names.  Process names should correspond to supervisord
process names.# die if the status of any of the


For the following process names, supervisord will tail the log of the process and attempt to verify that the
process has completed startup: solr_standalone, job_broker::rabbitmq.

=cut

sub test_with_supervisor($;$)
{
    my ( $func, $start_processes ) = @_;

    $start_processes ||= [];

    eval {
        MediaWords::Test::DB::test_on_test_database(
            sub {
                my ( $db ) = @_;

                _run_supervisord();

                my $status = `$_supervisorctl_bin status`;
                die( "bad supervisor status after startup: '$status'" ) if ( $status !~ /STOPPED|STARTING|RUNNING/ );

                _verify_processes_status( $db, $start_processes );
                _verify_processes_ready( $db, $start_processes );
                $func->( $db );
            }
        );
    };
    if ( $@ )
    {
        _run_supervisorctl( 'shutdown' );
        die( "error running supervisor test: '$@'" );
    }

    _run_supervisorctl( 'shutdown' );
}
