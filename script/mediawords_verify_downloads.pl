#!/usr/bin/env perl

# run through some number of random downloads and test each for whether the download is accessible
# from the indicated data store and, if not, through S3

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::KeyValueStore::AmazonS3;
use MediaWords::Util::Config qw(get_config);

my $_s3_store;

sub test_download
{
    my ( $db, $download ) = @_;

    say STDERR "testing $download->{ downloads_id }";

    my $store = ref( MediaWords::DBI::Downloads::_download_store_for_reading( $download ) );

    my $ret = {};

    my ( $store_error, $content_ref );
    eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download ); };
    if ( $@ || !$content_ref )
    {
        say STDERR "STORE ERROR: [$store] $@";
        $store_error = 1;
        $ret->{ $store } = 1;
    }

    if ( $store_error )
    {
        my $_s3_store ||= MediaWords::KeyValueStore::AmazonS3->new(
            {
                bucket_name    => get_config->{ amazon_s3 }->{ downloads }->{ bucket_name },
                directory_name => get_config->{ amazon_s3 }->{ downloads }->{ directory_name }
            }
        );
        eval { $content_ref = $_s3_store->fetch_content( $db, $download->{ downloads_id }, $download->{ path } ); };
        if ( $@ || !$content_ref )
        {
            say STDERR "S3 ERROR: $@";
            $ret->{ s3_backup } = 1;
        }
    }

    return $ret;
}

sub main
{
    my ( $num_tests ) = @ARGV;

    die( "$0 < num tests >" ) unless ( $num_tests );

    my $db = MediaWords::DB::connect_to_db;

    my ( $max_downloads_id ) = $db->query( "select downloads_id from downloads order by downloads_id desc limit 1" )->flat;

    my $num_tested_downloads = 0;
    my $all_test_results     = {};
    while ( $num_tested_downloads < $num_tests )
    {
        my $downloads_id = int( rand() * $max_downloads_id - 1_000_000 );
        say STDERR "rand id $num_tested_downloads: $downloads_id";

        my $download = $db->query( <<SQL, $downloads_id )->hash;
            select *
            from downloads
            where downloads_id = ?
              and state = 'success'
              -- File (no prefix), Tar ("tar:" prefix) and GridFS ("gridfs:"
              -- prefix) downloads are being stored in GridFS, so filter out
              -- those which aren't
              and path not like any(array['content%', 'postgresql%', 'amazon_s3%'])
SQL
        next unless ( $download );

        $num_tested_downloads++;

        my $test_results = test_download( $db, $download );

        my $any_error = 0;
        while ( my ( $store, $error ) = each( %{ $test_results } ) )
        {
            $all_test_results->{ $store }->{ error }++;
            push( @{ $all_test_results->{ $store }->{ error_downloads } }, $downloads_id );
            $any_error = $any_error || $error;
        }

        $all_test_results->{ all }++ if ( $any_error );
    }

    print Dumper( $all_test_results );
}

main();
