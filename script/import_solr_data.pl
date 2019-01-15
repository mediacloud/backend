#!/usr/bin/env perl
#
# Generate and import dumps of PostgreSQL data for Solr
#

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
        qw/daemon! queue_only! update! empty_queue! jobs=i throttle=i staging! full! stories_queue_table=s skip_logging!/ );

    if ( -f $solr_backup_lock_file )
    {
        die "Refusing to run while lock file $solr_backup_lock_file exists";
    }

    my $db = MediaWords::DB::connect_to_db;

    MediaWords::Solr::Dump::import_data( $db, $options );
}

main();

__END__
