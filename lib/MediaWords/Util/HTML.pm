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

#provide a procedural interface to HTML::Strip
# cpan the module should probably include this but it doesn't
sub html_strip
{

    # my $html_text = shift;
    # my $hs = HTML::Strip->new();
    # my $text = $hs->parse($html_text);
    # $hs->eof();
    #
    # return $text;
    return HTML::StripPP::strip( $_[ 0 ] ) || '';
}

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

1;
