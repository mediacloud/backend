#!/usr/bin/env perl

use forks;

# generate and import dumps of postgres data for solr
#
# usage: mediawords_import_solr_data.pl [ --delta ] [ --delete_all ] [ --solr_url ] [ --file <file 1> ... ]
#  --delta -- import stories that have changed since the last import
#  --delete_all -- delete all existing data from solr, in an atomic transaction with the import
#  --file -- import from a list of files rather than directly from postgres, files should be generated
#            with mediawords_generate_solr_dump.pl
#  --solr_url -- use the given solr_url to import rather than the solr_url in mediawords.yml

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

use Data::Dumper;

sub main
{
    my ( $delta, $file, $delete_all, $staging );

    $| = 1;

    Getopt::Long::GetOptions(
        "delta!"      => \$delta,
        "file!"       => \$file,
        "delete_all!" => \$delete_all,
        "staging!"    => \$staging,
    ) || return;

    if ( $file )
    {
        if ( $delete_all )
        {
            print STDERR "deleting all stories ...\n";
            MediaWords::Solr::Dump::delete_all_sentences( $staging ) || die( "delete all sentences failed." );
        }
        MediaWords::Solr::Dump::import_csv_files( [ @ARGV ], $delta, $staging );
    }
    else
    {
        MediaWords::Solr::Dump::generate_and_import_data( $delta, $delete_all, $staging );
    }
}

main();

__END__
