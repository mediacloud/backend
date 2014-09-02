#!/usr/bin/env perl
#
# Extract plain text corpus from Wikipedia XML dump
#
# Usage:
#   pv ltwiki-20121130-pages-articles-multistream.xml.bz2 | bzcat | ./extract_corpus_from_wikipedia.pl > corpus.txt
# or (without the progress bar):
#   bzcat ltwiki-20121130-pages-articles-multistream.xml.bz2 | ./extract_corpus_from_wikipedia.pl > corpus.txt
# or (if the dump is already extracted):
#   cat ltwiki-20121130-pages-articles-multistream.xml.bz2 | ./extract_corpus_from_wikipedia.pl > corpus.txt
#
# Run:
#   ./extract_corpus_from_wikipedia.pl --help
# for more options (e.g. input and output files).
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

# 'use MediaWords::CommonLibs' and others are omitted in order to make this tool more universal.
use Modern::Perl "2013";
use Readonly;
use Data::Dumper;

use utf8;
use Getopt::Long;
use XML::Parser;
use Text::MediawikiFormat 'wikiformat';
use HTML::FormatText;
use Text::Balanced qw (extract_bracketed extract_multiple);
use Regexp::Common qw /URI/;

# Global story separator (to be shared by the XML parser handlers;
# will be set to the value passed as a parameter)
my $global_story_separator = '----------------';

sub _wp_link
{
    my $link = shift;
    my $x = index( $link, '|' );
    return substr( $link, $x + 1 ) if $x != -1;
    return $link;
}

# Convert Media Wiki text to plain text
sub _strip_mediawiki_formatting($)
{
    my $text = shift;

    $text .= "\n";
    $text = "\n" . $text;

    # Remove interwiki links
    $text =~ s/\[\[[\w\-]{2,13}:.+?\]\]\n//gs;

    # Remove {{templates}} (might be nested, so use Text::Balanced for that)
    my @templates = extract_multiple( $text, [ sub { extract_bracketed( $text, '{{}}' ) } ], undef, 1 );
    foreach my $template ( @templates )
    {
        $text =~ s/\Q$template\E//gs;
    }

    # Remove headings (might be too repetitive for corpus, e.g. "References" or "See also")
    $text =~ s/^\s*?={2,6}.+?={2,6}\s*?$//mg;

    # Convert wiki -> HTML (slow)
    $text = wikiformat( $text, {}, { implicit_links => 1 } );

    # Convert HTML -> plain text
    $text = HTML::FormatText->format_string( $text, leftmargin => 0, rightmargin => 80 );

    # Remove REDIRECTs
    $text =~ s/REDIRECT//gs;

    # Remove <ref> and other tags
    $text =~ s|<ref.*?>.*?</ref>||gs;
    $text =~ s|<ref.*?/>||gs;

    # Remove images, leftover links, etc.
    $text =~ s/\[\[.+?\]\]//gs;

    # Remove leftover tags
    $text =~ s|<gallery.*?>.+?</gallery>||gs;
    $text =~ s|<nowiki\s*?/?>||gs;
    $text =~ s|<source.*?>.*?</source>||gs;
    $text =~ s|<references.*?/>||gs;
    $text =~ s|</gallery>||gs;
    $text =~ s|</nowiki>||gs;
    $text =~ s|<br\s*?/?>|\n|gs;
    $text =~ s|<onlyinclude>||gs;
    $text =~ s|</onlyinclude>||gs;
    $text =~ s|<includeonly>||gs;
    $text =~ s|</includeonly>||gs;
    $text =~ s|<noinclude>||gs;
    $text =~ s|</noinclude>||gs;
    $text =~ s|<poem>||gs;
    $text =~ s|</poem>||gs;
    $text =~ s|<ref>||gs;
    $text =~ s|</ref>||gs;
    $text =~ s|<math>.+?</math>||gs;
    $text =~ s|<imagemap>.+?</imagemap>||gs;
    $text =~ s|<span.*?>.*?</span>||gs;

    # Remove NOTOC
    $text =~ s/__NOTOC__//gs;

    # Remove URLs
    $text =~ s/$RE{URI}{HTTP}//gs;

    # Remove double spaces and line breaks
    $text =~ s/ +/ /gs;
    $text =~ s/\n\n+/\n\n/gs;

    # Remove separator if it is a part of the text
    $text =~ s/\n$global_story_separator\n//gs;
    $text =~ s/^$global_story_separator\n//gs;
    $text =~ s/\n$global_story_separator$//gs;

    return $text;
}

# Reference to the output handler (STDOUT or filehandle)
my $output_handle = 0;

# XML parser routines
{

    # Semi-global variable to note the start of the very first article
    # (so the script knows where to put story separators)
    my $first_article_started = 0;

    # Semi-global variable used by the XML parser to figure out whether or not the current
    # character data is part of the article text
    my $inside_article_text = 0;

    # String to which we append a single article (because XML::Parser somehow figures to return
    # the string data line-by-line)
    my $article_text = '';

    # "This event is generated when an XML start tag is recognized. Element is the name of the XML
    #  element type that is opened with the start tag. The Attr & Val pairs are generated for each
    #  attribute in the start tag."
    sub _xml_start
    {
        my ( $parser, $element, %attributes ) = @_;

        # Article text is located at mediawiki/page/revision/text
        if ( lc( $element ) eq 'text' )
        {
            $article_text        = '';
            $inside_article_text = 1;
        }
    }

    # "This event is generated when an XML end tag is recognized. Note that an XML empty tag
    #  (<foo/>) generates both a start and an end event."
    sub _xml_end
    {
        my ( $parser, $element ) = @_;

        # Article text is located at mediawiki/page/revision/text
        if ( lc( $element ) eq 'text' )
        {
            $inside_article_text = 0;

            # Add separator unless it is the very first article
            if ( !$first_article_started )
            {
                $first_article_started = 1;
            }
            else
            {
                print $output_handle "\n$global_story_separator\n\n";
            }

            # End of text
            $article_text = _strip_mediawiki_formatting( $article_text );
            print $output_handle $article_text;

            $article_text = '';
        }
    }

    # "This event is generated when non-markup is recognized. The non-markup sequence of characters
    #  is in String. A single non-markup sequence of characters may generate multiple calls to this
    #  handler. Whatever the encoding of the string in the original document, this is given to the
    #  handler in UTF-8."
    sub _xml_char
    {
        my ( $parser, $string ) = @_;

        if ( $inside_article_text )
        {
            $article_text .= $string;
        }
    }

    # "This is called at the start of a CDATA section."
    sub _xml_cdata_start
    {
        my ( $parser ) = @_;
    }

    # "This is called at the end of a CDATA section."
    sub _xml_cdata_end
    {
        my ( $parser ) = @_;
    }
}

# Extract plain text corpus from a Wikipedia XML dump
sub extract_corpus_from_wikipedia($$$)
{
    my ( $input_file, $output_file, $story_separator ) = @_;

    # Input file or STDIN
    if ( $input_file ne '-' )
    {
        open( INPUT, '<', $input_file ) or die $!;
    }
    else
    {
        *INPUT = *STDIN;
    }

    # Output file or STDOUT
    if ( $output_file ne '-' )
    {
        open( OUTPUT, '>', $output_file ) or die $!;
    }
    else
    {
        open( OUTPUT, '>&', \*STDOUT ) or die $!;
    }

    binmode( OUTPUT, ":utf8" );

    $output_handle          = \*OUTPUT;
    $global_story_separator = $story_separator;

    # Parse XML
    my $xml = new XML::Parser(
        ProtocolEncoding => 'UTF-8',
        Handlers         => {
            Start      => \&_xml_start,
            End        => \&_xml_end,
            Char       => \&_xml_char,
            CdataStart => \&_xml_cdata_start,
            CdataEnd   => \&_xml_cdata_end
        }
    );

    $xml->parse( *INPUT );

    # Cleanup
    close INPUT  unless $input_file eq '-';
    close OUTPUT unless $output_file eq '-';
}

sub main
{
    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    my $input_file      = '-';                   # Wikipedia XML dump file; default is STDIN
    my $output_file     = '-';                   # Corpus output file; default is STDOUT
    my $story_separator = '----------------';    # Delimiter to separate one story (article) from another

    my Readonly $usage =
      "Usage: $0" . ' [--input_file=wikipedia.xml]' . ' [--output_file=corpus.txt]' . '[--story_separator=----------------]';

    GetOptions(
        'input_file=s'      => \$input_file,
        'output_file=s'     => \$output_file,
        'story_separator=s' => \$story_separator
    ) or die "$usage\n";
    die "$usage\n" unless ( $input_file and $output_file );

    say STDERR "starting --  " . localtime();

    extract_corpus_from_wikipedia( $input_file, $output_file, $story_separator );

    say STDERR "finished --  " . localtime();
}

main();
