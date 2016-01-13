use strict;
use warnings;
use utf8;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
    use lib "$FindBin::Bin/../";
    use lib "$FindBin::Bin/";
}

use MediaWords::KeyValueStore::PostgreSQL;
use MediaWords::Test::DB;

require 'postgresql_tests.inc.pl';

MediaWords::Test::DB::test_on_test_database(
    sub {
        my ( $db ) = @_;

        my $postgresql = MediaWords::KeyValueStore::PostgreSQL->new(
            {
                database_label => undef,              # default database
                table          => 'raw_downloads',    #
            }
        );

        test_postgresql( $db, $postgresql );
    }
);
