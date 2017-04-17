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

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;
use MediaWords::Solr::Dump;
use Data::Dumper;
use Readonly;

# File that gets created when Solr shards are being backed up offsite
Readonly my $solr_backup_lock_file => '/tmp/solrbackup.lock';

sub main
{
    my ( $delta, $file, $delete_all, $staging, $jobs );

    $| = 1;

    Getopt::Long::GetOptions(
        "delta!"      => \$delta,
        "file!"       => \$file,
        "delete_all!" => \$delete_all,
        "staging!"    => \$staging,
        "jobs=i"      => \$jobs
    ) || return;

    if ( -f $solr_backup_lock_file )
    {
        die "Refusing to run while lock file $solr_backup_lock_file exists";
    }

    if ( $file )
    {
        if ( $delete_all )
        {
            INFO "deleting all stories ...";
            MediaWords::Solr::Dump::delete_all_sentences( $staging ) || die( "delete all sentences failed." );
        }
        MediaWords::Solr::Dump::import_csv_files( [ @ARGV ], $staging, $jobs );
    }
    else
    {
        MediaWords::Solr::Dump::generate_and_import_data( $delta, $delete_all, $staging, $jobs );
    }
}

main();

__END__
