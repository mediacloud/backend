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

sub bzip2($;$)
{
    my ( $data, $is_binary ) = @_;

    my $encoded_data;
    if ( $is_binary ) {
        $encoded_data = $data;
    } else {
        $encoded_data = MediaWords::Util::Text::encode_to_utf8( $data );
    }

    return MediaWords::Util::Compress::Proxy::bzip2( $encoded_data );
}

sub bunzip2($;$)
{
    my ( $data, $is_binary ) = @_;

    my $bunzipped2_data = MediaWords::Util::Compress::Proxy::bunzip2( $data );

    my $decoded_data;
    if ( $is_binary ) {
        $decoded_data = $bunzipped2_data;
    } else {
        $decoded_data = MediaWords::Util::Text::decode_from_utf8( $bunzipped2_data );
    }

    return $decoded_data;
}

sub gzip($;$)
{
    my ( $data, $is_binary ) = @_;

    my $encoded_data;
    if ( $is_binary ) {
        $encoded_data = $data;
    } else {
        $encoded_data = MediaWords::Util::Text::encode_to_utf8( $data );
    }

    return MediaWords::Util::Compress::Proxy::gzip( $encoded_data );
}

sub gunzip($;$)
{
    my ( $data, $is_binary ) = @_;

    my $gunzipped_data = MediaWords::Util::Compress::Proxy::gunzip( $data );

    my $decoded_data;
    if ( $is_binary ) {
        $decoded_data = $gunzipped_data;
    } else {
        $decoded_data = MediaWords::Util::Text::decode_from_utf8( $gunzipped_data );
    }

    return $decoded_data;
}

1;
