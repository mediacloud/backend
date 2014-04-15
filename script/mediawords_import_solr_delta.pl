#!/usr/bin/env perl

# generate delta csv dump and import it into solr

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use File::Temp;
use LWP::Simple;

use MediaWords::Solr::Dump;
use MediaWords::Util::Config;

sub main
{

    my $data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    my $dump_dir = "$data_dir/solr_dumps";

    mkdir( $dump_dir ) unless ( -d $dump_dir );

    my ( $fh, $filename ) = File::Temp::tempfile( 'solr-delta.csvXXXX', DIR => $dump_dir );
    close( $fh );

    print STDERR "generating dump ...\n";
    MediaWords::Solr::Dump::print_csv_to_file( $filename, 1, 1 );

    print STDERR "submitting dump ...\n";
    MediaWords::Solr::Dump::import_csv_files( [ $filename ], 1 );

    unlink( $filename );
}

main();
