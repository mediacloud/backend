#!/usr/bin/env perl

=head1 NAME

mediawords_gearman_worker.pl - Start one or all GJS workers; read configuration
from mediawords.yml.

This is a wrapper around gjs_worker.pl script.

The script reads configuration from mediawords.yml and passes it as parameters
to the gjs_worker.pl script.

=head1 SYNOPSIS

    # Run all Gearman functions from lib/MediaWords/GearmanFunction/
    ./script/run_with_carton.sh ./script/mediawords_gearman_worker.pl

or:

    # Run Gearman function "NinetyNineBottlesOfBeer" from "lib/MediaWords/GearmanFunction/"
    ./script/run_with_carton.sh ./script/mediawords_gearman_worker.pl NinetyNineBottlesOfBeer

or:

    # Run Gearman function from "path/to/NinetyNineBottlesOfBeer.pm"
    ./script/run_with_carton.sh ./script/mediawords_gearman_worker.pl path/to/NinetyNineBottlesOfBeer.pm

or:

    # Run all Gearman functions from "path_to/dir_with/gearman_functions/"
    ./script/run_with_carton.sh ./script/mediawords_gearman_worker.pl path_to/dir_with/gearman_functions/

=cut

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2012";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;
use Gearman::JobScheduler::Worker;
use MediaWords::Util::GearmanJobSchedulerConfiguration;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init( { level => $DEBUG, utf8 => 1, layout => "%d{ISO8601} [%P]: %m%n" } );

use Pod::Usage;
use Readonly;

# Default path to Media Cloud's directory of Gearman functions
my Readonly $MC_GEARMAN_FUNCTIONS_DIR = 'lib/MediaWords/GearmanFunction/';

sub main()
{
    if ( scalar( @ARGV ) > 1 )
    {
        pod2usage( 1 );
    }

    # Function name, path to function module or path to directory with all functions
    my $gearman_function_name_or_directory = $MC_GEARMAN_FUNCTIONS_DIR;
    if ( scalar( @ARGV ) == 1 )
    {
        $gearman_function_name_or_directory = $ARGV[ 0 ];
    }

    if ( -d $gearman_function_name_or_directory )
    {

        # Run all workers
        Gearman::JobScheduler::Worker::run_all_workers( $gearman_function_name_or_directory );

    }
    else
    {

        # Run single worker
        Gearman::JobScheduler::Worker::run_worker( $gearman_function_name_or_directory );
    }

}

main();
