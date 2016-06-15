#!/usr/bin/env perl

# generate csv dump of story_sentences and related tables for importing into solr

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Encode;
use Getopt::Long;
use Text::CSV_XS;

use MediaWords::DB;
use MediaWords::Solr::Dump;

sub main
{
    my ( $jobs, $file_spec, $max_proc, $min_proc, $delta ) = @_;

    Getopt::Long::GetOptions(
        "jobs=i"      => \$jobs,
        "max_proc=i"  => \$max_proc,
        "min_proc=i"  => \$min_proc,
        "file_spec=s" => \$file_spec,
        "delta!"      => \$delta
    ) || return;

    die(
"usage: $0 --file_spec <spec for file dump names> [ --jobs <num of parallel jobs> --max_proc <num> --min_proc <num> --delta ]"
    ) unless ( $file_spec );

    my $db = MediaWords::DB::connect_to_db;

    MediaWords::Solr::Dump::print_csv_to_file( $db, $file_spec, $jobs, $delta, $min_proc, $max_proc );

}

main();
