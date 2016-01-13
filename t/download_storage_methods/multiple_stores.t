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

use Test::More;
use MediaWords::KeyValueStore::AmazonS3;
use MediaWords::KeyValueStore::PostgreSQL;
use MediaWords::KeyValueStore::MultipleStores;
use MediaWords::Test::DB;

require 'amazon_s3_tests.inc.pl';
require 'postgresql_tests.inc.pl';

sub main()
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            my $postgresql = MediaWords::KeyValueStore::PostgreSQL->new(
                {
                    database_label => undef,              # default database
                    table          => 'raw_downloads',    #
                }
            );
            my $s3              = s3_download_handler( 'MediaWords::KeyValueStore::AmazonS3' );
            my $multiple_stores = MediaWords::KeyValueStore::MultipleStores->new(
                {
                    stores_for_reading => [ $postgresql, $s3 ],
                    stores_for_writing => [ $postgresql, $s3 ],
                }
            );

            test_postgresql( $db, $multiple_stores );
        }
    );
}

unless ( s3_tests_are_enabled() )
{
    plan skip_all => 'Amazon S3\'s testing bucket is not configured';
}
else
{
    main();
}
