use strict;
use warnings;

use Data::Dumper;
use Test::More;

use MediaWords::DB;
use MediaWords::Util::Config::Common;
use MediaWords::Util::Text;

sub s3_download_handler($)
{
    my $s3_handler_class = shift;

    my $s3_config = MediaWords::Util::Config::Common::amazon_s3_downloads();

    # We want to be able to run S3 tests in parallel
    my $test_suffix    = '-' . MediaWords::Util::Text::random_string( 64 );
    my $directory_name = $s3_config->directory_name() . $test_suffix;
    my $cache_table    = 'cache.s3_raw_downloads_cache';

    return $s3_handler_class->new(
        {
            access_key_id     => $s3_config->access_key_id(),
            secret_access_key => $s3_config->secret_access_key(),
            bucket_name       => $s3_config->bucket_name(),
            directory_name    => $directory_name,

            # Used only for CachedAmazonS3
            cache_table => $cache_table,
        }
    );
}

sub test_amazon_s3($;$)
{
    my ( $s3_handler_class, $create_mock_download ) = @_;

    my $s3_config = MediaWords::Util::Config::Common::amazon_s3_downloads();
    unless ( $s3_config->access_key_id() )
    {
        plan skip_all => 'Amazon S3 is not configured';
    }
    else
    {
        plan tests => 20;
    }

    my $db = MediaWords::DB::connect_to_db();

    my $test_downloads_id = 12345;
    if ( $create_mock_download )
    {
        require "$FindBin::Bin/helpers/create_mock_download.inc.pl";
        $test_downloads_id = create_mock_download( $db );
    }

    my $s3 = s3_download_handler( $s3_handler_class );
    ok( $s3, "Amazon S3 initialized" );

    my $test_downloads_path = undef;
    my $test_content        = 'Loren ipsum dolor sit amet.';
    my $content;

    #
    # Store content
    #

    my $s3_path;
    eval { $s3_path = $s3->store_content( $db, $test_downloads_id, $test_content ); };
    ok( ( !$@ ), "Storing content failed: $@" );
    ok( $s3_path, 'Object ID was returned' );
    like( $s3_path, qr#^s3:.+?/\Q$test_downloads_id\E$#, 'Object ID matches' );

    #
    # Fetch content, compare
    #

    eval { $content = $s3->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( ( !$@ ), "Fetching download failed: $@" );
    ok( defined $content, "Fetching download did not die but no content was returned" );
    is( $content, $test_content, "Content doesn't match." );

    #
    # Remove content, try fetching again
    #

    $s3->remove_content( $db, $test_downloads_id, $test_downloads_path );
    $content = undef;
    eval { $content = $s3->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( $@, "Fetching download that does not exist should have failed" );
    ok( ( !defined $content ),
        "Fetching download that does not exist failed (as expected) but the content was still returned" );

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
        $s3_path = $s3->store_content( $db, $test_downloads_id, $test_content );
        $s3_path = $s3->store_content( $db, $test_downloads_id, $test_content );
    };
    ok( ( !$@ ), "Storing content twice failed: $@" );
    ok( $s3_path, 'Object ID was returned' );
    like( $s3_path, qr#^s3:.+?/\Q$test_downloads_id\E$#, 'Object ID matches' );

    # Fetch content again, compare
    eval { $content = $s3->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( ( !$@ ), "Fetching download failed: $@" );
    ok( defined $content, "Fetching download did not die but no content was returned" );
    is( $content, $test_content, "Content doesn't match." );

    # Remove content, try fetching again
    $s3->remove_content( $db, $test_downloads_id, $test_downloads_path );
    $content = undef;
    eval { $content = $s3->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( $@, "Fetching download that does not exist should have failed" );
    ok( ( !defined $content ),
        "Fetching download that does not exist failed (as expected) but the content was still returned" );

    # Check if Amazon S3 thinks that the content exists
    ok(
        ( !$s3->content_exists( $db, $test_downloads_id, $test_downloads_path ) ),
        "content_exists() reports that content exists (although it shouldn't)"
    );
}

1;
