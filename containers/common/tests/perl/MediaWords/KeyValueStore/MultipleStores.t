#!/usr/bin/env prove

use strict;
use warnings;
use utf8;

use Test::More;
use FindBin;
use MediaWords::KeyValueStore::AmazonS3;
use MediaWords::KeyValueStore::PostgreSQL;
use MediaWords::KeyValueStore::MultipleStores;
use MediaWords::Util::Config::Common;

sub main()
{
    my $db = MediaWords::DB::connect_to_db();

    my $postgresql      = MediaWords::KeyValueStore::PostgreSQL->new( { table => 'raw_downloads' } );
    my $s3              = s3_download_handler( 'MediaWords::KeyValueStore::AmazonS3' );
    my $multiple_stores = MediaWords::KeyValueStore::MultipleStores->new(
        {
            stores_for_reading => [ $postgresql, $s3 ],
            stores_for_writing => [ $postgresql, $s3 ],
        }
    );

    test_postgresql( $db, $multiple_stores );
}

my $common_config = MediaWords::Util::Config::Common->new();
my $amazon_s3_downloads_config = $common_config->amazon_s3_downloads();
unless ( defined( $amazon_s3_downloads_config->access_key_id() ) )
{
    plan skip_all => 'Amazon S3\'s testing bucket is not configured';
}
else
{
    require "$FindBin::Bin/helpers/amazon_s3_tests.inc.pl";
    require "$FindBin::Bin/helpers/postgresql_tests.inc.pl";

    main();
}

