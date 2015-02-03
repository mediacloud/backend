use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 40;
use Readonly;

Readonly my $test_string      => "Media Cloud\r\nMedia Cloud\nMedia Cloud\r\n";
Readonly my $test_string_utf8 => "Media Cloud\r\nąčęėįšųūž\n您好\r\n";
Readonly my $empty_string     => '';

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::Compress' );
}

sub test_gzip()
{
    # Basic test
    my $gzipped_data = MediaWords::Util::Compress::gzip( $test_string );
    ok( length( $gzipped_data ), 'Length of gzipped data is non-zero' );
    isnt( $gzipped_data, $test_string, 'Gzipped data and source string differ' );
    my $gunzipped_data = MediaWords::Util::Compress::gunzip( $gzipped_data );
    is( $gunzipped_data, $test_string, 'Gunzipped data matches source string' );

    # Empty string
    Readonly my $empty_string => '';
    $gzipped_data = MediaWords::Util::Compress::gzip( $empty_string );
    ok( length( $gzipped_data ), 'Length of gzipped zero-length data is non-zero' );
    $gunzipped_data = MediaWords::Util::Compress::gunzip( $gzipped_data );
    is( $gunzipped_data, $empty_string, 'Gunzipped data matches empty string' );

    # Bad input
    eval { MediaWords::Util::Compress::gzip( undef ) };
    ok( $@, 'Undefined input for gzip' );
    eval { MediaWords::Util::Compress::gunzip( undef ) };
    ok( $@, 'Undefined input for gunzip' );
    eval { MediaWords::Util::Compress::gunzip( '' ) };
    ok( $@, 'Empty input for gunzip' );
    eval { MediaWords::Util::Compress::gunzip( 'No way this is valid Gzip data' ) };
    ok( $@, 'Invalid input for gunzip' );
}

sub test_gzip_encode()
{
    # Basic test
    my $gzipped_data = MediaWords::Util::Compress::encode_and_gzip( $test_string_utf8 );
    ok( length( $gzipped_data ), 'Length of gzipped data is non-zero' );
    isnt( $gzipped_data, $test_string_utf8, 'Gzipped data and source string differ' );
    my $gunzipped_data = MediaWords::Util::Compress::gunzip_and_decode( $gzipped_data );
    is( $gunzipped_data, $test_string_utf8, 'Gunzipped data matches source string' );

    # Empty string
    Readonly my $empty_string => '';
    $gzipped_data = MediaWords::Util::Compress::encode_and_gzip( $empty_string );
    ok( length( $gzipped_data ), 'Length of gzipped zero-length data is non-zero' );
    $gunzipped_data = MediaWords::Util::Compress::gunzip_and_decode( $gzipped_data );
    is( $gunzipped_data, $empty_string, 'Gunzipped data matches empty string' );

    # Bad input
    eval { MediaWords::Util::Compress::encode_and_gzip( undef ) };
    ok( $@, 'Undefined input for encode_and_gzip' );
    eval { MediaWords::Util::Compress::gunzip_and_decode( undef ) };
    ok( $@, 'Undefined input for gunzip_and_decode' );
    eval { MediaWords::Util::Compress::gunzip_and_decode( '' ) };
    ok( $@, 'Empty input for gunzip_and_decode' );
    eval { MediaWords::Util::Compress::gunzip_and_decode( 'No way this is valid Gzip data' ) };
    ok( $@, 'Invalid input for gunzip_and_decode' );
}

sub test_bzip2()
{
    # Basic test
    my $bzip2ped_data = MediaWords::Util::Compress::bzip2( $test_string );
    ok( length( $bzip2ped_data ), 'Length of bzip2ped data is non-zero' );
    isnt( $bzip2ped_data, $test_string, 'Bzip2ped data and source string differ' );
    my $bunzip2ped_data = MediaWords::Util::Compress::bunzip2( $bzip2ped_data );
    is( $bunzip2ped_data, $test_string, 'Bunzip2ped data matches source string' );

    # Empty string
    $bzip2ped_data = MediaWords::Util::Compress::bzip2( $empty_string );
    ok( length( $bzip2ped_data ), 'Length of bzip2ped zero-length data is non-zero' );
    $bunzip2ped_data = MediaWords::Util::Compress::bunzip2( $bzip2ped_data );
    is( $bunzip2ped_data, $empty_string, 'Bunzip2ped data matches empty string' );

    # Bad input
    eval { MediaWords::Util::Compress::bzip2( undef ) };
    ok( $@, 'Undefined input for bzip2' );
    eval { MediaWords::Util::Compress::bunzip2( undef ) };
    ok( $@, 'Undefined input for bunzip2' );
    eval { MediaWords::Util::Compress::bunzip2( '' ) };
    ok( $@, 'Empty input for bunzip2' );
    eval { MediaWords::Util::Compress::bunzip2( 'No way this is valid Bzip2 data' ) };
    ok( $@, 'Invalid input for bunzip2' );
}

sub test_bzip2_encode()
{
    # Basic test
    my $bzip2ped_data = MediaWords::Util::Compress::encode_and_bzip2( $test_string_utf8 );
    ok( length( $bzip2ped_data ), 'Length of bzip2ped data is non-zero' );
    isnt( $bzip2ped_data, $test_string_utf8, 'Bzip2ped data and source string differ' );
    my $bunzip2ped_data = MediaWords::Util::Compress::bunzip2_and_decode( $bzip2ped_data );
    is( $bunzip2ped_data, $test_string_utf8, 'Bunzip2ped data matches source string' );

    # Empty string
    $bzip2ped_data = MediaWords::Util::Compress::encode_and_bzip2( $empty_string );
    ok( length( $bzip2ped_data ), 'Length of bzip2ped zero-length data is non-zero' );
    $bunzip2ped_data = MediaWords::Util::Compress::bunzip2_and_decode( $bzip2ped_data );
    is( $bunzip2ped_data, $empty_string, 'Bunzip2ped data matches empty string' );

    # Bad input
    eval { MediaWords::Util::Compress::encode_and_bzip2( undef ) };
    ok( $@, 'Undefined input for encode_and_bzip2' );
    eval { MediaWords::Util::Compress::bunzip2_and_decode( undef ) };
    ok( $@, 'Undefined input for bunzip2_and_decode' );
    eval { MediaWords::Util::Compress::bunzip2_and_decode( '' ) };
    ok( $@, 'Empty input for bunzip2_and_decode' );
    eval { MediaWords::Util::Compress::bunzip2_and_decode( 'No way this is valid Bzip2 data' ) };
    ok( $@, 'Invalid input for bunzip2_and_decode' );
}

sub test_wrong_algorithm()
{
    eval { MediaWords::Util::Compress::bunzip2( MediaWords::Util::Compress::gzip( $test_string ) ) };
    ok( $@, 'String compressed with Gzip, trying to uncompress with Bzip2' );
    eval { MediaWords::Util::Compress::gunzip( MediaWords::Util::Compress::bzip2( $test_string ) ) };
    ok( $@, 'String compressed with Bzip2, trying to uncompress with Gzip' );
}

sub main()
{
    test_gzip();
    test_gzip_encode();
    test_bzip2();
    test_bzip2_encode();
    test_wrong_algorithm();
}

main();
