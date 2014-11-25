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

    return MediaWords::Thrift::Extractor::extract_html( $raw_html );
}

1;
