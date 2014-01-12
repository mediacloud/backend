use strict;

use MediaWords::Util::Config;

use Test::More;

my $settings = MediaWords::Util::Config::get_config->{ amazon_s3 }->{ test };
unless ( $settings )
{
    plan skip_all => 'Amazon S3\'s testing bucket is not configured';
}
else
{
    plan tests => 20;
}

use Data::Dumper;
use MediaWords::DBI::Downloads::Store::AmazonS3;
use MediaWords::DB;

my $s3 = MediaWords::DBI::Downloads::Store::AmazonS3->new( { use_testing_database => 1 } );
ok( $s3, "Amazon S3 initialized" );

my $db = MediaWords::DB::connect_to_db;
ok( $db, "PostgreSQL initialized " );

my $test_download_id = 999999999999999;
my $test_download    = { downloads_id => $test_download_id };
my $test_content     = 'Loren ipsum dolor sit amet.';
my $content_ref;

#
# Store content
#

my $s3_path;
my $expected_path;
eval { $s3_path = $s3->store_content( $db, $test_download, \$test_content ); };
ok( ( !$@ ), "Storing content failed: $@" );
ok( $s3_path, 'Object ID was returned' );
$expected_path = 's3:' . $settings->{ downloads_folder_name } .
  ( substr( $settings->{ downloads_folder_name }, -1, 1 ) ne '/' ? '/' : '' ) . $test_download->{ downloads_id };
is( $s3_path, $expected_path, 'Object ID matches' );

#
# Fetch content, compare
#

eval { $content_ref = $s3->fetch_content( $db, $test_download ); };
ok( ( !$@ ), "Fetching download failed: $@" );
ok( $content_ref, "Fetching download did not die but no content was returned" );
is( $$content_ref, $test_content, "Content doesn't match." );

#
# Remove content, try fetching again
#

$s3->remove_content( $db, $test_download );
$content_ref = undef;
eval { $content_ref = $s3->fetch_content( $db, $test_download ); };
ok( $@, "Fetching download that does not exist should have failed" );
ok( ( !$content_ref ),
    "Fetching download that does not exist failed (as expected) but the content reference ($content_ref) was returned" );

#
# Check if Amazon S3 thinks that the content exists
#
ok( ( !$s3->content_exists( $db, $test_download ) ),
    "content_exists() reports that content exists (although it shouldn't)" );

#
# Store content twice
#

my $s3_path;
eval {
    $s3_path = $s3->store_content( $db, $test_download, \$test_content );
    $s3_path = $s3->store_content( $db, $test_download, \$test_content );
};
ok( ( !$@ ), "Storing content twice failed: $@" );
ok( $s3_path, 'Object ID was returned' );
$expected_path = 's3:' . $settings->{ downloads_folder_name } .
  ( substr( $settings->{ downloads_folder_name }, -1, 1 ) ne '/' ? '/' : '' ) . $test_download->{ downloads_id };
is( $s3_path, $expected_path, 'Object ID matches' );

# Fetch content again, compare
eval { $content_ref = $s3->fetch_content( $db, $test_download ); };
ok( ( !$@ ), "Fetching download failed: $@" );
ok( $content_ref, "Fetching download did not die but no content was returned" );
is( $$content_ref, $test_content, "Content doesn't match." );

# Remove content, try fetching again
$s3->remove_content( $db, $test_download );
$content_ref = undef;
eval { $content_ref = $s3->fetch_content( $db, $test_download ); };
ok( $@, "Fetching download that does not exist should have failed" );
ok( ( !$content_ref ),
    "Fetching download that does not exist failed (as expected) but the content reference ($content_ref) was returned" );

# Check if Amazon S3 thinks that the content exists
ok( ( !$s3->content_exists( $db, $test_download ) ),
    "content_exists() reports that content exists (although it shouldn't)" );
