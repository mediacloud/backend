package MediaWords::Test::DB;

=head1 NAME

MediaWords::Test::Supervisor - functions for starting up supervisord processes for usse in tests

=head1 SYNOPSIS

    sub do_tests { # do some tests }

    MediaWords::Test::Supervisor::run_with_superisord( \&do_tests, [ qw/solr_standalone extract_and_vector/ ] )

=head1 DESCRIPTION

This module handles starting and stopping supervisord processes for the sake of unit tests.

=cut

use strict;
use warnings;

use Readonly;

use MediaWords::Util::Paths;

# seconds to wait for solr to start accepting queries
Readonly my $SOLR_START_TIMEOUT => 90;

# seconds to wait for solr to complete install if solr log reports that it is installing
Readonly my $SOLR_INSTALL_TIMEOUT => 90;

# mediacloud root path and supervisor scripts
my $_mc_root_path      = MediaWords::Util::Paths::mc_root_path();
my $_supervisord_bin   = "$_mc_root_path/supervisor/supervisord.sh";
my $_supervisorctl_bin = "$_mc_root_path/supervisor/supervisorctl.sh";

# if there is a function for a given process in this hash, that function is called to verify
# that the process is ready for work (for instance that solr is ready for queries).  Wait while polling
# if necessary until the process is ready (or die if there is an indication that the process is not ready)
my $_process_ready_functions = {
    'solr_standalone'     => \&_solr_standalone_ready,
    'job_broker:rabbitmq' => \&_rabbit_ready
};

# poll every second for $SOLR_START_TIMEOUT seconds.  return once an http request to solr succeeds.  die if the supervisor
# status is every anthing but RUNNING or if the $solr_timeout is reached.  If the solr_standalone log is downloading
# the solr distribution, go into a separate poll loop waiting for up to $SOLR_INSTALL_TIMEOUT for the solr install to
# finish.
sub _solr_standalone_ready()
{
    my $tail          = _run_supervisorctl( 'tail solr_standalone stderr' );
    my $is_installing = ( $tail =~ /Downloading Solr/ );

    my $solr_timeout = $is_installing ? $SOLR_INSTALL_TIMEOUT : $SOLR_START_TIMEOUT;
    while ( $solr_timeout-- > 0 )
    {
        my $status = _run_supervisorctl( 'status solr_standalone' );
        die( "bad solr status: '$status'" ) unless ( $status =~ /RUNNING/ );

        # try to execute a simple solr query; if no error is thrown, it worked and solr is up
        eval { MediaWords::Solr::query( { q => '*:*', rows => 0 } ) };
        return unless ( $@ );

        sleep 5;
    }

    die( "solr failed to start after timeout" );
}

sub _rabbit_ready()
{
    return;
}

# run supervisorctl with the given string as the argument, return the stdout of the call
sub _run_supervisorctl($)
{
    my ( $arg ) = @_;

    my $output = `$_supervisorctl_bin $arg`;

    return $output;
}

# if any of the given processes are not running, start them.  die if any of the given processes are still not running.
sub _verify_processes_status
{
    my ( $processes ) = @_;

    my $status = _run_supervisor_ctl( 'status' );

    for my $process ( @{ $processes } )
    {
        die( "no such process '$process'" ) unless ( $status =~ /^\Q${process}\E/ );

        my $process_running_re = qr/(\Q${process}\E|\Q${process}\E:\Q${process}\E_\d\d)\s+RUNNING)/;

        if ( $status =~ $process_running_re )
        {
            _run_supervisorctl( 'start $process' );
        }

        $status = _run_supervisorctl( 'status' );

        die( '$process not running' ) unless ( $status =~ $process_running_re );
    }
}

sub _verify_processes_ready
{
    my ( $processes ) = @_;

    for my $process ( @{ $processes } )
    {
        if ( my $func = $_process_ready_functions->{ $process } )
        {
            $func->();
        }
    }
}

=head2 run_with_supervisor( $func [ , $start_processes ]  )

Start supervisord, verify that the given processes are running, run the given function, and then stop supervisord.

Will die if supervisord is already running, if supervisord does not start, or if any of the jobs cannot be started.

Supervisord will start in the default configuration (see docs/supervisord.markdown).

$start_processes should be a reference to an array of process names.  Process names should correspond to supervisord
process names.# die if the status of any of the


For the following process names, supervisord will tail the log of the process and attempt to verify that the
process has completed startup: solr_standalone, job_broker::rabbitmq.

=cut

sub run_with_supervisor($;$)
{
    my ( $func, $start_processes ) = @_;

    $start_processes ||= [];

    my $supervisord_errors = `$_supervisord_bin`;
    die( "error starting supervisord: '$supervisord_errors'" ) if ( $supervisord_errors );

    eval {
        my $status = `$_supervisorctl_bin status`;
        die( "bad supervisor status after startup: '$status'" ) if ( $status =~ /topic_snapshot/ );

        _verify_processes_status( $start_processes );

        _verify_processes_ready( $start_processes );

        $func->();
    };

    my $supervisor_shutdown = `$_supervisorctl_bin shutdown`;
    die( "error shutting down supervisord: '$supervisor_shutdown'" ) unless ( $supervisor_shutdown eq 'Shut down' );
}
