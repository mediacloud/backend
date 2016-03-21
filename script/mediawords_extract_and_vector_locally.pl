#!/usr/bin/env perl
#
# Run a loop extracting the text of any downloads that have not been extracted
# yet locally (not on Gearman)
#
# Usage: mediawords_extract_and_vector_locally.pl [<num of processes>] [<number of total jobs>] [<number of this job>]
#
# Example:
#
# mediawords_extract_and_vector_locally.pl 20 2 1
# (extracts with 20 total processes, divided into 2 jobs, of which this is the first one)
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Util::Process;

use MediaWords::DB;
use MediaWords::GearmanFunction::ExtractAndVector;
use Readonly;

# number of downloads to fetch at a time
Readonly my $PROCESS_SIZE => 100;

# extract, story, and tag downloaded text a slice of downloads.
# downloads are extracted by a total of num_total_jobs processings
# a total of num_total_processes, with a unique 1-indexed job_number
# for each job
sub extract_text($$$$)
{
    my ( $process_num, $num_total_processes, $num_total_jobs, $job_number ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    my $job_process_num = $process_num + int( ( $num_total_processes / $num_total_jobs ) * ( $job_number - 1 ) );

    while ( 1 )
    {

        say STDERR "[$process_num, $job_process_num] find new downloads...";

        my $downloads = $db->query(
            <<EOF,

            SELECT downloads_id
            FROM downloads
            WHERE extracted = 'f'
              AND type = 'content'
              AND state = 'success'
              AND (( ( stories_id + ? ) % ? ) = 0 )
            ORDER BY stories_id ASC
            LIMIT ?
EOF
            $job_process_num, $num_total_processes, $PROCESS_SIZE
        );

        my $at_least_one_download_found = 0;
        while ( my $download = $downloads->hash() )
        {
            $at_least_one_download_found = 1;
            my $return_value = 0;

            eval {

                # Run the Gearman function locally
                $return_value = MediaWords::GearmanFunction::ExtractAndVector->run_locally( $download );

            };
            if ( $@ or ( !$return_value ) )
            {

                # Probably the download was not found (Gearman function will
                # take care of writing an error message to the database, so we
                # only output an error here)
                say STDERR "Extractor died while processing download " . $download->{ downloads_id } . ": $@\n";

            }

        }

        if ( !$at_least_one_download_found )
        {
            say STDERR "[$process_num] no downloads found. sleeping ...";
            sleep 60;
        }

    }
}

# fork of $num_processes
sub main
{
    my $mod;

    if ( scalar( @ARGV ) >= 2 )
    {
        if ( $ARGV[ 0 ] eq '--mod' )
        {
            shift @ARGV;

            $mod = shift @ARGV;
        }
    }

    my ( $num_total_processes, $num_total_jobs, $job_number ) = @ARGV;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    $num_total_processes ||= 1;
    $num_total_jobs      ||= 1;
    $job_number          ||= 1;

    # turn off buffering so processes don't write over each other as much
    $| = 1;

    my $num_processes = int( $num_total_processes / $num_total_jobs );

    if ( defined( $mod ) )
    {
        while ( 1 )
        {
            eval {
                say STDERR "[$mod] START";
                extract_text( $mod, $num_total_processes, $num_total_jobs, $job_number );
            };
            if ( $@ )
            {
                say STDERR "[$mod] extract_text failed with error: $@";
                say STDERR "[$mod] sleeping before restart ...";
                sleep 60;
            }
        }
    }
    else
    {
        for ( my $i = 0 ; $i < $num_processes ; $i++ )
        {
            if ( !mc_fork )
            {
                exec( __FILE__, '--mod', $i, $num_total_processes, $num_total_jobs, $job_number );
            }
        }

        while ( wait > -1 )
        {
        }
    }
}

main();
