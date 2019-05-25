use strict;
use warnings;
use utf8;

use FindBin;

use MediaWords::DB;
use MediaWords::KeyValueStore::PostgreSQL;

require "$FindBin::Bin/helpers/postgresql_tests.inc.pl";

my $db = MediaWords::DB::connect_to_db();

my $postgresql = MediaWords::KeyValueStore::PostgreSQL->new( { table => 'raw_downloads' } );

test_postgresql( $db, $postgresql );
