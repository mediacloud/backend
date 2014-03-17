package MediaWords::Util::Compress;

# Data compression / decompression helper package

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Encode;
use IO::Compress::Gzip qw(:level);
use IO::Uncompress::Gunzip qw();

# Encode data into UTF-8; die() on error
sub _encode_to_utf8($)
{
    my $data = shift;

    # Will croak on error
    return Encode::encode( 'utf-8', $data );
}

# Decode data from UTF-8; die() on error
sub _decode_from_utf8($)
{
    my $data = shift;

    # Will croak on error
    return Encode::decode( 'utf-8', $data );
}

# Gzip data; die() on error
sub gzip($)
{
    my $data = shift;

    my $gzipped_data;

    if ( !( IO::Compress::Gzip::gzip \$data => \$gzipped_data, -Level => Z_BEST_COMPRESSION, Minimal => 1 ) )
    {
        die "Unable to Gzip data: $IO::Compress::Gzip::GzipError\n";
    }

    return $gzipped_data;
}

# Encode and gzip data; die() on error
sub encode_and_gzip($)
{
    my $data = shift;

    my $encoded_data = _encode_to_utf8( $data );
    my $gzipped_data = gzip( $encoded_data );

    return $gzipped_data;
}

# Gunzip data; die() on error
sub gunzip($)
{
    my $data = shift;

    my $gunzipped_data;

    if ( !( IO::Uncompress::Gunzip::gunzip \$data => \$gunzipped_data ) )
    {
        die "Unable to Gunzip data: $IO::Uncompress::Gunzip::GunzipError\n";
    }

    return $gunzipped_data;
}

# Gunzip and decode data; die() on error
sub gunzip_and_decode($)
{
    my $data = shift;

    my $gunzipped_data = gunzip( $data );
    my $decoded_data   = _decode_from_utf8( $gunzipped_data );

    return $decoded_data;
}

1;
