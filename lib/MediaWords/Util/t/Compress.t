use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 34;
use Readonly;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::Compress' );
}

sub test_gzip_encode($)
{
    my $test_string = shift;

    my $gzipped_data = MediaWords::Util::Compress::encode_and_gzip( $test_string );
    ok( length( $gzipped_data ), 'Length of gzipped data is non-zero' );
    isnt( $gzipped_data, $test_string, 'Gzipped data and source string differ' );
    my $gunzipped_data = MediaWords::Util::Compress::gunzip_and_decode( $gzipped_data );
    is( $gunzipped_data, $test_string, 'Gunzipped data matches source string' );
}

sub test_bzip2_encode($)
{
    my $test_string = shift;

    my $bzip2ped_data = MediaWords::Util::Compress::encode_and_bzip2( $test_string );
    ok( length( $bzip2ped_data ), 'Length of bzip2ped data is non-zero' );
    isnt( $bzip2ped_data, $test_string, 'Bzip2ped data and source string differ' );
    my $bunzip2ped_data = MediaWords::Util::Compress::bunzip2_and_decode( $bzip2ped_data );
    is( $bunzip2ped_data, $test_string, 'Bunzip2ped data matches source string' );
}

sub test_wrong_algorithm($)
{
    my $test_string = shift;

    eval { MediaWords::Util::Compress::bunzip2( MediaWords::Util::Compress::gzip( $test_string ) ) };
    ok( $@, 'String compressed with Gzip, trying to uncompress with Bzip2' );
    eval { MediaWords::Util::Compress::gunzip( MediaWords::Util::Compress::bzip2( $test_string ) ) };
    ok( $@, 'String compressed with Bzip2, trying to uncompress with Gzip' );
}

sub test_bad_input()
{
    eval { MediaWords::Util::Compress::encode_and_gzip( undef ) };
    ok( $@, 'Undefined input for encode_and_gzip' );
    eval { MediaWords::Util::Compress::gunzip_and_decode( undef ) };
    ok( $@, 'Undefined input for gunzip_and_decode' );
    eval { MediaWords::Util::Compress::gunzip_and_decode( '' ) };
    ok( $@, 'Empty input for gunzip_and_decode' );
    eval { MediaWords::Util::Compress::gunzip_and_decode( 'No way this is valid Gzip data' ) };
    ok( $@, 'Invalid input for gunzip_and_decode' );

    eval { MediaWords::Util::Compress::encode_and_bzip2( undef ) };
    ok( $@, 'Undefined input for encode_and_bzip2' );
    eval { MediaWords::Util::Compress::bunzip2_and_decode( undef ) };
    ok( $@, 'Undefined input for bunzip2_and_decode' );
    eval { MediaWords::Util::Compress::bunzip2_and_decode( '' ) };
    ok( $@, 'Empty input for bunzip2_and_decode' );
    eval { MediaWords::Util::Compress::bunzip2_and_decode( 'No way this is valid Bzip2 data' ) };
    ok( $@, 'Invalid input for bunzip2_and_decode' );
}

sub main()
{
    Readonly my @test_strings => (

        # ASCII
        "Media Cloud\r\nMedia Cloud\nMedia Cloud\r\n",

        # UTF-8
        "Media Cloud\r\nąčęėįšųūž\n您好\r\n",

        # Empty string
        "",
    );

    foreach my $test_string ( @test_strings )
    {
        test_gzip_encode( $test_string );
        test_bzip2_encode( $test_string );
        test_wrong_algorithm( $test_string );
    }

    test_bad_input();
}

main();
