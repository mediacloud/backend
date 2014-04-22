#!/usr/bin/env perl

# import a list of csvs into solr and write the dataimport.properties with the import date

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Solr::Dump;

sub main
{
    my $files = [ @ARGV ];

    die( "usage: $0 <file 1> <file 2> ..." ) unless ( @{ $files } );

    MediaWords::Solr::Dump::import_csv_files( $files );
}

main();
