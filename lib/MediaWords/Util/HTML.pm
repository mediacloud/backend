package MediaWords::Util::HTML;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various functions for manipulating html

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(html_strip clear_cruft_text);

# various functions for editing feed and medium tags

use strict;
use HTML::StripPP;
use HTML::Entities qw( decode_entities  );
use Devel::Peek qw(Dump);
use Encode;
use List::Util qw(min);

use XML::LibXML;

my $xml_parser = XML::LibXML->new(
    {

        no_network   => 1,
        load_ext_dtd => 0,
        no_defdtd    => 1,
        recover      => 2,

        # Assume that HTML pages will be full of errors and thus the only thing
        # that matters is whether or not the module is able to cough up some
        # sort of an XML file
        suppress_errors   => 1,
        suppress_warnings => 1,
    }
);

# provide a procedural interface to HTML::Strip
# use HTML::StripPP instead of HTML::Strip b/c HTML::Strip mucks up the encoding
sub html_strip
{

    # use HTML::Strip;

    # my $html_text = shift;
    # my $hs = HTML::Strip->new();
    # my $text = $hs->parse($html_text);
    # $hs->eof();
    #
    # return $text;

    #
    # TODO HACK to prevent StripPP from segfaulting.
    # This appears to be necessary on Perl 5.8 but not on 5.10.
    #

    if ( !defined( $_[ 0 ] ) )
    {
        return '';
    }

    if ( ( length( $_[ 0 ] ) > 14000 ) )
    {
        my $max_segment_length = 14000;

        my $str_pos = 0;

        my $ret;

        while ( $str_pos < length( $_[ 0 ] ) )
        {

            #perldoc: index STR,SUBSTR,POSITION

            my $new_line_pos = index( $_[ 0 ], "\n", $str_pos + 5000 );

            my $new_line_segment_length;

            if ( $new_line_pos == -1 )
            {
                $new_line_segment_length = $max_segment_length;
            }
            else
            {
                $new_line_segment_length = $new_line_pos - $str_pos;
            }

            my $segment_length = min( $new_line_segment_length, $max_segment_length );

            my $token_end_pos = index( $_[ 0 ], ">", $str_pos + 5000 ) + 1;

            my $token_boundary_segment_length;

            if ( $token_end_pos == 0 )
            {
                $token_boundary_segment_length = $max_segment_length;
            }
            else
            {
                $token_boundary_segment_length = $token_end_pos - $str_pos;
            }

            $segment_length = min( $segment_length, $token_boundary_segment_length );

            #say STDERR "segment_length $segment_length";
            #$DB::signal = 2;

            #say STDERR "segment \n" .  substr ($_[ 0 ], $str_pos, $segment_length);

            $ret .= HTML::StripPP::strip( substr( $_[ 0 ], $str_pos, $segment_length ) );
            $str_pos += $segment_length;
        }

        return $ret;
    }

    return HTML::StripPP::strip( $_[ 0 ] ) || '';
}

# old version of html_strip that tries to work around HTML::Strip encoding problem
sub html_strip_encoding_fix
{
    my $html_text = shift;

    #my $hs = HTML::Strip->new();
    #my $text = $hs->parse($html_text);
    #$hs->eof()HTML::Strip;

    #work around a bug in HTML::Strip see http://rt.cpan.org/Public/Bug/Display.html?id=42834
    my $decoded_html = $html_text;

    #eval {say STDERR Dump($decoded_html)};

    my $hs = HTML::Strip->new( decode_entities => 0 );
    my $utf8_html;

    #$utf8_html = decode("UTF-8",encode("UTF-8",decode("UTF-8", $decoded_html )));

    #say STDERR "starting decode";

    $utf8_html = $decoded_html;

    eval {
        if ( !utf8::is_utf8( $utf8_html ) )
        {
            $utf8_html = decode( "UTF-8", $decoded_html );
        }
    };
    my $err = $@;
    if ( $err )
    {
        say STDERR "Error decoding: $err";
    }

    #say STDERR "finished decode";
    #say STDERR Dump($utf8_html);

    #eval { say STDERR "utf8_encoded: '$utf8_html'" };

    my $utf8_text = $utf8_html;
    utf8::encode( $utf8_html );
    $utf8_text = $hs->parse( $utf8_html );

    #eval {say STDERR "html_stripped $utf8_text" };
    #say STDERR Dump($utf8_text);
    my $decoded_text = decode( "utf-8", $utf8_text );

    #say STDERR "UTF8 decoded $decoded_text";
    #say STDERR Dump($decoded_text);

    #return $decoded_text;
    $decoded_text = HTML::Entities::decode_entities( $decoded_text );

    #$decoded_text .= ' ';
    #say STDERR "decoded entities $decoded_text";
    #utf8::decode(utf8::encode($decoded_text));
    #say STDERR Dump($decoded_text);
    return $decoded_text;
}

# Cleans up the UTF-8 markup by tidying it up into a valid XML file.
# Also removes:
# * Contents outside "<body>...</body>";
# * Contents of "<script>", "<style>", "<frame>", "<applet>", "<textarea>";
# * Empty HTML comments;
# * "<" and ">" in HTML comments.
# die()s on error.
sub clear_cruft_text($)
{
    my $html = shift;

    eval { $html = $xml_parser->load_html( string => $html ); };

    # Ignore errors (in $@) because HTML::LibXML is likely to complain a lot

    unless ( $html )
    {
        die "LibXML succeeded, but the resulting HTML file is empty.\n";
    }

    # Scrub contents of various tags
    my @scrub_tags = qw/script style frame applet textarea/;
    foreach my $tag ( @scrub_tags )
    {
        my @nodelist = $html->getElementsByTagName( $tag );
        foreach my $node ( @nodelist )
        {
            # Set the text contents of the node to ' ' so that the node doesn't get "<closed />"
            $node->removeChildNodes();
            $node->appendText( ' ' );
        }
    }

    # Process HTML comments
    for my $comment ( $html->findnodes( '//comment()' ) )
    {
        my $data = $comment->data;

        if ( $data eq '' )
        {
            # Remove empty HTML comments
            $comment->parentNode->removeChild( $comment );
        }
        else
        {
            # Remove newlines in HTML comments
            $data =~ s/[\r\n]/ /g;

            # Remove ">" and "<" in HTML comments
            $data =~ s/[<>]/|/g;
            $comment->setData( $data );
        }
    }

    # Try to find only the "<body>" element; if it is present, leave only <body>
    my @bodies = $html->getElementsByTagName( 'body' );
    if ( scalar @bodies == 0 )
    {
        # No "<body>" - do nothing
    }
    elsif ( scalar @bodies == 1 )
    {
        # Single "<body>" element - use it
        $html = $bodies[ 0 ];
    }
    elsif ( scalar @bodies > 1 )
    {
        # Multiple "<body>" elements - use the last one
        $html = $bodies[ -1 ];
    }

    $html = $html->toString( 1 ) . "\n";

    return $html;
}

# Returns true if HTML has "click print" comments
sub has_clickprint($)
{
    my $html = shift;

    return ( $html =~ /<\!--\s*startclickprintinclude\s*-->/i );
}

1;
