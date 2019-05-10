package MediaWords::Job::ImportSolrDataForTesting;

#
# Import test data to Solr; called by tests
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Solr::Dump;

# Run job
sub run($;$)
{
    my ( $class, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    INFO "Importing test Solr data...";

    MediaWords::Solr::Dump::import_data( $db, $args );

    INFO "Done importing test Solr data.";
}

no Moose;    # gets rid of scaffolding

1;
