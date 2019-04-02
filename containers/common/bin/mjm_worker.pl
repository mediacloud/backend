#!/usr/bin/env perl

=head1 NAME

mjm_worker.pl - Start MediaWords::JobManager::Job worker

=head1 SYNOPSIS

    # Run instance of the "NinetyNineBottlesOfBeer" function
    mjm_worker.pl NinetyNineBottlesOfBeer

or:

    # Run instance of the function from "path/to/NinetyNineBottlesOfBeer.pm"
    mjm_worker.pl path/to/NinetyNineBottlesOfBeer.pm

=cut

use strict;
use warnings;
use Modern::Perl "2015";

use FindBin;

# Include workers from the current path and its lib/
use lib "./";
use lib "./lib/";

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../samples";

use MediaWords::JobManager::Worker;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init( { level => $DEBUG, utf8 => 1, layout => "%d{ISO8601} [%P]: %m%n" } );

use Pod::Usage;

sub main()
{
    # Function name, path to function module or path to directory with all functions
    unless ( scalar( @ARGV ) == 1 )
    {
        pod2usage( 1 );
    }
    my $function_name_or_directory = $ARGV[ 0 ];

    # Run single worker
    MediaWords::JobManager::Worker::start_worker( $function_name_or_directory );
}

main();
