use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
    use lib "$FindBin::Bin/../";
}

use Test::More;

use MediaWords::Util::Config;

my $config = MediaWords::Util::Config::get_config;
unless ( $config->{ amazon_s3 }->{ test } )
{
    plan skip_all => 'Amazon S3\'s testing bucket is not configured';
}
else
{
    plan tests => 20;
}

use Data::Dumper;
use MediaWords::KeyValueStore::AmazonS3;
use MediaWords::Test::DB;

MediaWords::Test::DB::test_on_test_database(
    sub {
        my $db = shift;

        ok( $db, "PostgreSQL initialized " );

        my $s3 = MediaWords::KeyValueStore::AmazonS3->new(
            {
                bucket_name    => $config->{ amazon_s3 }->{ test }->{ bucket_name },
                directory_name => $config->{ amazon_s3 }->{ test }->{ directory_name }
            }
        );
        ok( $s3, "Amazon S3 initialized" );

        my $test_downloads_id   = 999999999999999;
        my $test_downloads_path = undef;
        my $test_content        = 'Loren ipsum dolor sit amet.';
        my $content_ref;

        #
        # Store content
        #

        my $s3_path;
        my $expected_path;
        eval { $s3_path = $s3->store_content( $db, $test_downloads_id, \$test_content ); };
        ok( ( !$@ ), "Storing content failed: $@" );
        ok( $s3_path, 'Object ID was returned' );
        $expected_path =
          's3:' . $config->{ amazon_s3 }->{ test }->{ directory_name } .
          ( substr( $config->{ amazon_s3 }->{ test }->{ directory_name }, -1, 1 ) ne '/' ? '/' : '' ) . $test_downloads_id;
        is( $s3_path, $expected_path, 'Object ID matches' );

        #
        # Fetch content, compare
        #

        eval { $content_ref = $s3->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
        ok( ( !$@ ), "Fetching download failed: $@" );
        ok( $content_ref, "Fetching download did not die but no content was returned" );
        is( $$content_ref, $test_content, "Content doesn't match." );

        #
        # Remove content, try fetching again
        #

        $s3->remove_content( $db, $test_downloads_id, $test_downloads_path );
        $content_ref = undef;
        eval { $content_ref = $s3->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
        ok( $@, "Fetching download that does not exist should have failed" );
        ok( ( !$content_ref ),
            "Fetching download that does not exist failed (as expected) but the content reference was returned" );

        #
        # Check if Amazon S3 thinks that the content exists
        #
        ok(
            ( !$s3->content_exists( $db, $test_downloads_id, $test_downloads_path ) ),
            "content_exists() reports that content exists (although it shouldn't)"
        );

        #
        # Store content twice
        #

        $s3_path = undef;
        eval {
            $s3_path = $s3->store_content( $db, $test_downloads_id, \$test_content );
            $s3_path = $s3->store_content( $db, $test_downloads_id, \$test_content );
        };
        ok( ( !$@ ), "Storing content twice failed: $@" );
        ok( $s3_path, 'Object ID was returned' );
        $expected_path =
          's3:' . $config->{ amazon_s3 }->{ test }->{ directory_name } .
          ( substr( $config->{ amazon_s3 }->{ test }->{ directory_name }, -1, 1 ) ne '/' ? '/' : '' ) . $test_downloads_id;
        is( $s3_path, $expected_path, 'Object ID matches' );

        # Fetch content again, compare
        eval { $content_ref = $s3->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
        ok( ( !$@ ), "Fetching download failed: $@" );
        ok( $content_ref, "Fetching download did not die but no content was returned" );
        is( $$content_ref, $test_content, "Content doesn't match." );

        # Remove content, try fetching again
        $s3->remove_content( $db, $test_downloads_id, $test_downloads_path );
        $content_ref = undef;
        eval { $content_ref = $s3->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
        ok( $@, "Fetching download that does not exist should have failed" );
        ok( ( !$content_ref ),
            "Fetching download that does not exist failed (as expected) but the content reference was returned" );

        # Check if Amazon S3 thinks that the content exists
        ok(
            ( !$s3->content_exists( $db, $test_downloads_id, $test_downloads_path ) ),
            "content_exists() reports that content exists (although it shouldn't)"
        );
    }
);
