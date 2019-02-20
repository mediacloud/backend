package MediaWords::Job::Facebook::ImportSolrDataForTesting;

#
# Import test data to Solr; called by tests
#
# Start this worker script by running:
#
# ./script/run_in_env.sh mjm_worker.pl lib/MediaWords/Job/ImportSolrDataForTesting.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Test::Solr;
use MediaWords::Solr::Dump;

# Run job
sub run($;$)
{
    my ( $class, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    INFO "Importing test Solr data...";

    MediaWords::Solr::Dump::import_data( $db, $args );

    INFO "Done imporing test Solr data.";
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
