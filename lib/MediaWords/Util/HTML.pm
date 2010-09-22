package MediaWords::Util::HTML;

# various functions for manipulating html

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(html_strip);

# various functions for editing feed and medium tags

use strict;
use HTML::StripPP;
use HTML::Entities qw( decode_entities  );
use Devel::Peek qw(Dump);
use Encode;
use List::Util qw(min);

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

    if (length ($_[ 0 ] ) > 14000)
    {
	my $max_segment_length = 14000;

	my $str_pos = 0;

	my $ret;

	while ( $str_pos < length($_[ 0 ] ) )
	{

	    my $new_line_pos = index ($_[0], $str_pos + 5000, "\n");

	    my $segment_length = $new_line_pos - $str_pos;

	    if ($new_line_pos == -1)
	      {
		$segment_length = $max_segment_length;
	      }

	    $segment_length = min($segment_length, $max_segment_length);

	    #say STDERR "segment_length $segment_length";

	    $ret .= HTML::StripPP::strip( substr ($_[ 0 ], $str_pos, $segment_length) );
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

# A custom string escape for JavaScript
sub javascript_escape
{
    use MediaWords::Util::HTML;

    my ( $s ) = @_;

    $s = MediaWords::Util::HTML::html_strip( $s );

    $s =~ s/'/\\'/g;

    return $s;
}

1;
