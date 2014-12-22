package MediaWords::Util::ThriftExtractor;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various helper functions for downloads

use strict;

use Carp;
use Scalar::Defer;
use Readonly;
use MediaWords::Thrift::Extractor;

sub get_extracted_html
{
    my ( $raw_html ) = @_;

    my $html_blocks = MediaWords::Thrift::Extractor::extract_html( $raw_html );

    my $ret = join( "\n\n", @$html_blocks );

    utf8::upgrade( $ret );

    die unless Encode::is_utf8( $ret );

    return $ret;
}

1;
