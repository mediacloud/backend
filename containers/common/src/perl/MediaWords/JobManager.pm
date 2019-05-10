package MediaWords::JobManager;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use UUID::Tiny ':std';
use Digest::SHA qw(sha256_hex);
use Carp;
use Readonly;

# flush sockets after every write
$| = 1;

# Max. job ID length for MediaWords::JobManager jobs (when
# MediaWords::JobManager::Job comes up with a job ID of its own)
Readonly my $MJM_JOB_ID_MAX_LENGTH => 256;

# (static) Return an unique job ID that will identify a particular job with its
# arguments
#
# * function name, e.g. 'NinetyNineBottlesOfBeer'
# * hashref of job arguments, e.g. "{ 'how_many_bottles' => 13 }"
#
# Returns: SHA256 of the unique job ID, e.g. "18114c0e14fe5f3a568f73da16130640b1a318ba"
# (SHASUM of "NinetyNineBottlesOfBeer(how_many_bottles_=_2000)"
#
# FIXME maybe use Data::Dumper?
sub unique_job_id($$)
{
    my ( $function_name, $job_args ) = @_;

    unless ( $function_name )
    {
        return undef;
    }

    # Convert to string
    $job_args =
      ( $job_args and scalar keys %{ $job_args } )
      ? join( ', ', map { $_ . ' = ' . ( $job_args->{ $_ } // 'undef' ) } sort( keys %{ $job_args } ) )
      : '';
    my $unique_id = "$function_name($job_args)";

    # Job broker might limit the length of "unique" parameter
    $unique_id = sha256_hex( $unique_id );

    return $unique_id;
}

# (static) Return an unique, path-safe job name which is suitable for writing
# to the filesystem (e.g. for logging)
#
# Parameters:
# * function name, e.g. 'NinetyNineBottlesOfBeer'
# * hashref of job arguments, e.g. "{ 'how_many_bottles' => 13 }"
# * (optional) Job ID, e.g. "H:tundra.home:18" or "127.0.0.1:4730//H:tundra.home:18"
#
# Returns: unique job ID, e.g.:
# * "084567C4146F11E38F00CB951DB7256D.NinetyNineBottlesOfBeer(how_many_bottles_=_2000)", or
# * "H_tundra.home_18.NinetyNineBottlesOfBeer(how_many_bottles_=_2000)"
sub _unique_path_job_id($$;$)
{
    my ( $function_name, $job_args, $job_id ) = @_;

    unless ( $function_name )
    {
        return undef;
    }

    my $unique_id;
    if ( $job_id )
    {

        # If job ID was passed as a parameter, this means that the job
        # was run remotely (by running run_remotely() or add_to_queue()).
        # Thus, the job has to be logged to a location that can later be found
        # by knowing the job ID.

        my $broker = MediaWords::AbstractJob::broker();

        # Strip the host part (if present)
        $unique_id = $broker->job_id_from_handle( $job_id );

    }
    else
    {

        # If no job ID was provided, this means that the job is being
        # run locally.
        # The job's output still has to be logged somewhere, so we generate an
        # UUID to serve in place of job ID.

        my $uuid = uc( create_uuid_as_string( UUID_RANDOM ) );
        $uuid =~ s/\-//gs;

        $unique_id = $uuid;
    }

    # ID goes first in case the job name shortener decides to cut out a part of the job ID
    my $mjm_job_id = $unique_id . '.' . unique_job_id( $function_name, $job_args );
    if ( length( $mjm_job_id ) > $MJM_JOB_ID_MAX_LENGTH )
    {
        $mjm_job_id = substr( $mjm_job_id, 0, $MJM_JOB_ID_MAX_LENGTH );
    }

    # Sanitize for paths
    $mjm_job_id = _sanitize_for_path( $mjm_job_id );

    return $mjm_job_id;
}

sub _sanitize_for_path($)
{
    my $string = shift;

    $string =~ s/[^a-zA-Z0-9\.\-_\(\)=,]/_/gi;

    return $string;
}

1;
