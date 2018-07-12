package MediaWords::Util::Compress;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

use MediaWords::Util::Text;

{

    package MediaWords::Util::Compress::Proxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;    # set PYTHONPATH too

    import_python_module( __PACKAGE__, 'mediawords.util.compress' );

    1;
}

sub extract_tarball_to_directory($$;$)
{
    my ( $archive_file, $dest_directory, $strip_root ) = @_;

    return MediaWords::Util::Compress::Proxy::extract_tarball_to_directory( $archive_file, $dest_directory, $strip_root );
}

sub extract_zip_to_directory($$)
{
    my ( $archive_file, $dest_directory ) = @_;

    return MediaWords::Util::Compress::Proxy::extract_zip_to_directory( $archive_file, $dest_directory );
}

sub bzip2($)
{
    my $data = shift;

    my $encoded_data = MediaWords::Util::Text::encode_to_utf8( $data );

    return MediaWords::Util::Compress::Proxy::bzip2( $encoded_data );
}

sub bunzip2($)
{
    my $data = shift;

    my $bunzipped2_data = MediaWords::Util::Compress::Proxy::bunzip2( $data );

    my $decoded_data = MediaWords::Util::Text::decode_from_utf8( $bunzipped2_data );

    return $decoded_data;
}

sub gzip($)
{
    my $data = shift;

    my $encoded_data = MediaWords::Util::Text::encode_to_utf8( $data );

    return MediaWords::Util::Compress::Proxy::gzip( $encoded_data );
}

sub gunzip($)
{
    my $data = shift;

    my $gunzipped_data = MediaWords::Util::Compress::Proxy::gunzip( $data );

    my $decoded_data = MediaWords::Util::Text::decode_from_utf8( $gunzipped_data );

    return $decoded_data;
}

1;
