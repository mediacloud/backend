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

require 'amazon_s3_set_credentials_from_env.inc.pl';
set_amazon_s3_test_credentials_from_env_if_needed();

my $config = MediaWords::Util::Config::get_config;
unless ( defined( $config->{ amazon_s3 }->{ test } ) )
{
    plan skip_all => 'Amazon S3\'s testing bucket is not configured';
}
else
{
    require 'amazon_s3_tests.inc.pl';
    require 'postgresql_tests.inc.pl';

    main();
}
