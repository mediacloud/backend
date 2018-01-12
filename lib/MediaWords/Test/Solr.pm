package MediaWords::Test::Solr;

=head1 NAME

MediaWords::Test::Supervisor - functions for using solr during testing

=head1 SYNOPSIS

    MediaWords::Test::Solr::set_test_index( $db )
=cut

use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use MediaWords::Solr;
use MediaWords::Solr::Dump;

# remember that we already swapped the solr live collection
my $_swapped_live_collection;

=head2 setup_test_index( $db )

Switch the active sole index to the staging collection.  Delete everything currently in that collection.  Run a
full solr import based on the current postgres db.

Using this function leaves the side effect of leaving all of the test data sitting in the staging collection after
it has been run.

Due to a failsafe built into MediaWords::Solr::Dump::generate_and_import_data, the delete of the staging collection
data will fail if there are more than 100 million sentences in the index (to prevent accidental deletion of
production data).

The function assumes that whichever solr collection is live when it is first called is the live collection.  It will
use the other collection no matter how many times it is called.

=cut

sub setup_test_index($)
{
    my ( $db ) = @_;

    if ( !MediaWords::Test::DB::using_test_database() )
    {
        LOGDIE( 'setup_test_index can only be called while connected to postgres test database' );
    }

    if ( !$_swapped_live_collection )
    {
        MediaWords::Solr::swap_live_collection( $db );
        $_swapped_live_collection = 1;
    }

    MediaWords::Solr::Dump::delete_all_stories( $db );
    MediaWords::Solr::Dump::queue_all_stories( $db );
    MediaWords::Solr::Dump::import_data( $db, { full => 1 } );
}

1;
