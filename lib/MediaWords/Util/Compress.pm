package MediaWords::Util::Compress;

# Data compression / decompression helper package

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::Util::Text;

use IO::Compress::Gzip qw(:level);
use IO::Uncompress::Gunzip qw($GunzipError);
use IO::Compress::Bzip2 qw();
use IO::Uncompress::Bunzip2 qw($Bunzip2Error);

# Bzip2 data; die() on error
sub bzip2($)
{
    my $data = shift;
    unless ( defined $data )
    {
        die "Data to bzip2 is undefined.";
    }

    my $bzipped2_data;

    unless ( IO::Compress::Bzip2::bzip2 \$data => \$bzipped2_data, BlockSize100K => 9 )
    {
        die "Unable to Bzip2 data: $IO::Compress::Bzip2::Bzip2Error\n";
    }

    unless ( defined $bzipped2_data )
    {
        die "Bzip2ped data is undefined.";
    }

    return $bzipped2_data;
}

# Encode and Bzip2 data; die() on error
sub encode_and_bzip2($)
{
    my $data = shift;
    unless ( defined $data )
    {
        die "Data to encode and bzip2 is undefined.";
    }

    my $encoded_data  = MediaWords::Util::Text::encode_to_utf8( $data );
    my $bzipped2_data = bzip2( $encoded_data );

    return $bzipped2_data;
}

# Bunzip2 data; die() on error
sub bunzip2($)
{
    my $data = shift;
    unless ( defined $data )
    {
        die "Data to bunzip2 is undefined.";
    }
    if ( $data eq '' )
    {
        die 'Data is empty (no way an empty string is a valid Bzip2 archive)';
    }

    # Using OO interface because it supports Transparent and Strict options
    my $z = new IO::Uncompress::Bunzip2 \$data,
      Transparent => 0,
      Strict      => 1
      or die "Unable to Bunzip2 data: $Bunzip2Error\n";
    my $bunzipped2_data;
    if ( $z->eof() )
    {
        # Because when an uncompressed string is empty, <$z> returns undef
        # instead of empty string
        $bunzipped2_data = '';
    }
    else
    {
        local $/;
        $bunzipped2_data = <$z>;
    }

    unless ( defined $bunzipped2_data )
    {
        die "Bunzipped2 data is undefined.";
    }

    return $bunzipped2_data;
}

# Bunzip2 and decode data; die() on error
sub bunzip2_and_decode($)
{
    my $data = shift;
    unless ( defined $data )
    {
        die "Data to bunzip2 and decode is undefined.";
    }
    if ( $data eq '' )
    {
        die 'Data is empty (no way an empty string is a valid Bzip2 archive)';
    }

    my $bunzipped2_data = bunzip2( $data );
    my $decoded_data    = MediaWords::Util::Text::decode_from_utf8( $bunzipped2_data );

    return $decoded_data;
}

# Gzip data; die() on error
sub gzip($)
{
    my $data = shift;
    unless ( defined $data )
    {
        die "Data to gzip is undefined.";
    }

    my $gzipped_data;

    unless ( IO::Compress::Gzip::gzip \$data => \$gzipped_data, -Level => Z_BEST_COMPRESSION, Minimal => 1 )
    {
        die "Unable to Gzip data: $IO::Compress::Gzip::GzipError\n";
    }

    unless ( defined $gzipped_data )
    {
        die "Gzipped data is undefined.";
    }

    return $gzipped_data;
}

# Encode and Gzip data; die() on error
sub encode_and_gzip($)
{
    my $data = shift;
    unless ( defined $data )
    {
        die "Data to encode and gzip is undefined.";
    }

    my $encoded_data = MediaWords::Util::Text::encode_to_utf8( $data );
    my $gzipped_data = gzip( $encoded_data );

    return $gzipped_data;
}

# Gunzip data; die() on error
sub gunzip($)
{
    my $data = shift;
    unless ( defined $data )
    {
        die "Data to gunzip is undefined.";
    }
    if ( $data eq '' )
    {
        die 'Data is empty (no way an empty string is a valid Gzip archive)';
    }

    # Using OO interface because it supports Transparent and Strict options
    my $z = new IO::Uncompress::Gunzip \$data,
      Transparent => 0,
      Strict      => 1
      or die "Unable to Gunzip data: $GunzipError\n";
    my $gunzipped_data;
    if ( $z->eof() )
    {
        # Because when an uncompressed string is empty, <$z> returns undef
        # instead of empty string
        $gunzipped_data = '';
    }
    else
    {
        local $/;
        $gunzipped_data = <$z>;
    }

    unless ( defined $gunzipped_data )
    {
        die "Gunzipped data is undefined.";
    }

    return $gunzipped_data;
}

# Gunzip and decode data; die() on error
sub gunzip_and_decode($)
{
    my $data = shift;
    unless ( defined $data )
    {
        die "Data to gunzip and decode is undefined.";
    }
    if ( $data eq '' )
    {
        die 'Data is empty (no way an empty string is a valid Gzip archive)';
    }

    my $gunzipped_data = gunzip( $data );
    my $decoded_data   = MediaWords::Util::Text::decode_from_utf8( $gunzipped_data );

    return $decoded_data;
}

1;
