#!/usr/bin/env perl

# run a loop extracting the text of any downloads that have not been extracted yet

# usage: mediawords_extract_text.pl [<num of processes>] [<number of total jobs>] [<number of this job>]
#
# example:
# mediawords_extract_text.pl 20 2 1
# (extracts with 20 total processes, divided into 2 jobs, of which this is the first one)

# number of downloads to fetch at a time
use constant PROCESS_SIZE => 100;

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::MC_Fork;
use Perl6::Say;

# fork of $num_processes
sub main
{
    my ( $num_total_processes, $num_total_jobs, $job_number ) = @ARGV;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    # turn off buffering so processes don't write over each other as much
    $| = 1;

    #my $num_processes = int( $num_total_processes / $num_total_jobs );

    while ( 1 )
    {
        sleep( 2 );

        say STDERR "heart beat...";

        sleep( 5 );

    }
}

main();
