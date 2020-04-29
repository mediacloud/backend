#!/usr/bin/env perl

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Job::Broker;
use MediaWords::Solr::Dump;


sub run_job($)
{
    my $args = shift;

    my $db = MediaWords::DB::connect_to_db();

    unless ( $args ) {
        $args = {};
    }

    INFO "Importing test Solr data with arguments " . Dumper( $args ) . "...";

    MediaWords::Solr::Dump::import_data( $db, $args );

    INFO "Done importing test Solr data.";
}

sub main()
{
    my $app = MediaWords::Job::Broker->new( 'MediaWords::Job::ImportSolrDataForTesting' );
    $app->start_worker( \&run_job );
}

main();
