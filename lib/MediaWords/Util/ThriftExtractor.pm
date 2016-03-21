package MediaWords::Util::ThriftExtractor;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

# various helper functions for downloads

use strict;
use warnings;

use Carp;
use Scalar::Defer;
use Readonly;
use MediaWords::Thrift::Extractor;

sub extractor_version
{
    return 'readability-lxml-0.3.0.5';
}

sub get_extracted_html
{
    my ( $raw_html ) = @_;

    return '' unless ( $raw_html );

    unless ( Encode::is_utf8( $raw_html ) )
    {
        die "HTML to be extracted is not UTF-8.";
    }

    my $html_blocks = MediaWords::Thrift::Extractor::extract_html( $raw_html );

    my $ret = join( "\n\n", @$html_blocks );

    utf8::upgrade( $ret );

    unless ( Encode::is_utf8( $ret ) )
    {
        die "Extracted text is not UTF-8.";
    }

    return $ret;
}

1;
