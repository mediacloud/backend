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

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;
use MediaWords::DB;
use MediaWords::Solr::Dump;
use Data::Dumper;
use Readonly;

# File that gets created when Solr shards are being backed up offsite
Readonly my $solr_backup_lock_file => '/tmp/solrbackup.lock';

sub main
{
    $| = 1;

    my $options = {};

    Getopt::Long::GetOptions( $options,
        qw/queue_only! update! empty_queue! jobs=i throttle=i staging! full! stories_queue_table=s skip_logging!/ );

    if ( -f $solr_backup_lock_file )
    {
        die "Refusing to run while lock file $solr_backup_lock_file exists";
    }

    my $db = MediaWords::DB::connect_to_db;

    MediaWords::Solr::Dump::import_data( $db, $options );
}

main();

__END__
