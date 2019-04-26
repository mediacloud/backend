use strict;
use warnings;

# test AbstractJob functionality

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Util::ParseJSON;
use MediaWords::DB;

use Sys::Hostname;

use Test::More;

{

    package MediaWords::Job::StatefulJobTest;

    use Moose;
    with 'MediaWords::AbstractStatefulJob';

    sub run($$$)
    {
        my ( $self, $db, $args ) = @_;

        my $test = $args->{ test };
        if ( $test eq 'null' )
        {
            # null test
        }
        elsif ( $test eq 'error' )
        {
            die( "test error" );
        }
        elsif ( $test eq 'running' )
        {
            die( $MediaWords::AbstractStatefulJob::DIE_WITHOUT_ERROR_TAG );
        }
        elsif ( $test eq 'custom' )
        {
            MediaWords::Job::StatefulJobTest->update_job_state_message( $db, 'custom message' );
            die( $MediaWords::AbstractStatefulJob::DIE_WITHOUT_ERROR_TAG );
        }
        else
        {
            die( "uknown test: $test" );
        }
    }

    no Moose;    # gets rid of scaffolding
}

{

    package MediaWords::Job::StatelessJobTest;

    use Moose;
    with 'MediaWords::AbstractStatefulJob';

    sub run($;$)
    {
        return 'run';
    }

    no Moose;    # gets rid of scaffolding
}

# test that the given test with run() above results in the given job state
sub test_job_state($$$;$)
{
    my ( $db, $test, $state, $message ) = @_;

    my $label = "$test / $state";

    MediaWords::Job::StatefulJobTest->run( { test => $test } );

    my $js = $db->query( "select * from job_states order by job_states_id desc limit 1" )->hash;

    ok( $js, "$label: job_states row exists" );

    is( $js->{ state }, $state, "$label state" );

    if ( $message )
    {
        my $got_message = $js->{ message } || '';
        ok( $got_message =~ /\Q$message\E/, "$label message '$got_message' matches pattern '$message'" );
    }

    is( $js->{ class },      'MediaWords::Job::StatefulJobTest',                    "$label class" );
    is( $js->{ hostname },   Sys::Hostname::hostname(),                             "$label hostname" );
    is( $js->{ process_id }, $$,                                                    "$label process_id" );
    is( $js->{ priority },   $MediaWords::JobManager::Job::MJM_JOB_PRIORITY_NORMAL, "$label priority" );

    my $json_data = MediaWords::Util::ParseJSON::decode_json( $js->{ args } );
    is( $json_data->{ test }, $test, "$label args JSON test" );
}

# test the stateful job functinoality of AbstractJob
sub test_stateful_job($)
{
    my ( $db ) = @_;

    is( MediaWords::Job::StatelessJobTest->run( {} ), 'run', 'stateless job run' );

    test_job_state( $db, 'null',    'completed' );
    test_job_state( $db, 'error',   'error', 'test error' );
    test_job_state( $db, 'running', 'running' );
    test_job_state( $db, 'custom',  'running', 'custom message' );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_stateful_job( $db );

    done_testing();
}

main();
