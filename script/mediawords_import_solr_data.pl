#!/usr/bin/env perl

use forks;

# generate and import dumps of postgres data for solr

use strict;
use warnings;

use Sys::RunAlone;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::Solr::Dump;

sub main
{
    my ( $delta, $file, $delete );

    $| = 1;

    Getopt::Long::GetOptions(
        "delta!"  => \$delta,
        "file!"   => \$file,
        "delete!" => \$delete,
    ) || return;

    if ( $file )
    {
        if ( $delete )
        {
            print STDERR "deleting all stories ...\n";
            MediaWords::Solr::Dump::delete_all_sentences() || die( "delete all sentences failed." );
        }
        MediaWords::Solr::Dump::import_csv_files( [ @ARGV ], $delta );
    }
    else
    {
        MediaWords::Solr::Dump::generate_and_import_data( $delta, $delete );
    }
}

main();

__END__
