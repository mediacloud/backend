package MediaWords::Controller::Admin::Gearman;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use parent 'Catalyst::Controller';
use File::Slurp;
use Readonly;

Readonly my $MAX_LOG_SIZE => 1024 * 1024 * 64;

sub index : Path : Args(0)
{
    return 'Nothing here.';
}

# view Gearman job log
sub view_log : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $job_id = $c->req->param( 'job_id' );

    my $job = $db->query(
        <<EOF,
        SELECT *
        FROM gearman_job_queue
        WHERE job_handle = ?
EOF
        $job_id
    )->hash;

    if ( $job->{ status } ne 'enqueued' )
    {
        $job->{ log_path } =
          Gearman::JobScheduler::log_path_for_gearman_job( $job->{ function_name }, $job->{ job_handle } );
    }
    else
    {
        $job->{ log_path } = undef;
    }

    my $log = '';
    unless ( -e $job->{ log_path } )
    {
        $log = 'File at the log path does not exist.';
    }
    else
    {
        my $log_size = -s $job->{ log_path };
        if ( $log_size > $MAX_LOG_SIZE )
        {
            $log = "Log is too big (takes up $log_size bytes, but I am limited to $MAX_LOG_SIZE bytes.";
        }
        else
        {

            $log = read_file( $job->{ log_path } );

        }
    }

    $c->stash->{ job }      = $job;
    $c->stash->{ log }      = $log;
    $c->stash->{ template } = 'gearman/view_log.tt2';
}

1;
