use strict;
use warnings;
use utf8;

use MediaWords::KeyValueStore::PostgreSQL;
use MediaWords::Test::DB;

require 'helpers/postgresql_tests.inc.pl';

MediaWords::Test::DB::test_on_test_database(
    sub {
        my ( $db ) = @_;

        my $postgresql = MediaWords::KeyValueStore::PostgreSQL->new( { table => 'raw_downloads' } );

        test_postgresql( $db, $postgresql );
    }
);
