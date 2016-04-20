package MediaWords::Util::HTML;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

# various functions for manipulating html

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(html_strip);

# various functions for editing feed and medium tags

use HTML::Entities qw( decode_entities  );
use Devel::Peek qw(Dump);
use Encode;
use List::Util qw(min);
use Memoize;
use Tie::Cache;
use Text::Trim;

my @_block_level_element_tags =
  qw/h1 h2 h3 h4 h5 h6 p div dl dt dd ol ul li dir menu address blockquote center div hr ins noscript pre/;
my $_tag_list                 = join '|', ( map { quotemeta $_ } ( @_block_level_element_tags ) );
my $_block_level_start_tag_re = qr{< (:? $_tag_list ) (:? > | \s )}ix;
my $_block_level_end_tag_re   = qr{</ (:? $_tag_list ) >}ix;

sub contains_block_level_tags
{
    my ( $string ) = @_;

    return 1 if ( $string =~ $_block_level_start_tag_re );

    return 1 if ( $string =~ $_block_level_end_tag_re );

    return 0;
}

sub new_lines_around_block_level_tags
{
    my ( $string ) = @_;

    return $string if ( !contains_block_level_tags( $string ) );

    $string =~ s/($_block_level_start_tag_re)/\n\n$1/gsxi;

    $string =~ s/($_block_level_end_tag_re)/$1\n\n/gsxi;

    return $string;
}

# Cache output of html_strip() because it is likely that it is going to be called multiple times from extractor
my %_html_strip_cache;
tie %_html_strip_cache, 'Tie::Cache', {
    MaxCount => 1024,          # 1024 entries
    MaxBytes => 1024 * 1024    # 1 MB of space
};

memoize 'html_strip', SCALAR_CACHE => [ HASH => \%_html_strip_cache ];

# Strip the html tags, html comments, any any text within TITLE, SCRIPT, APPLET, OBJECT, and STYLE tags
# Code by powerman from: http://www.perlmonks.org/?node_id=161281
# Don't use HTML::Strip because it "mucks up the encoding"
sub html_strip($)
{
    my ( $html ) = @_;

    $html = new_lines_around_block_level_tags( $html );

    unless ( defined $html )
    {
        return '';
    }

    # Remove soft hyphen (&shy; or 0xAD) character from text
    # (some news websites hyphenate their stories using this character so that the browser can lay it out more nicely)
    my $soft_hyphen = chr( 0xAD );
    $html =~ s/$soft_hyphen//gs;

    # ALGORITHM:
    #   find < ,
    #       comment <!-- ... -->,
    #       or comment <? ... ?> ,
    #       or one of the start tags which require correspond
    #           end tag plus all to end tag
    #       or if \s or ="
    #           then skip to next "
    #           else [^>]
    #   >
    $html =~ s{
    <               # open tag
    (?:             # open group (A)
      (!--) |       #   comment (1) or
      (\?) |        #   another comment (2) or
      (?i:          #   open group (B) for /i
        ( TITLE  |  #     one of start tags
          SCRIPT |  #     for which
          APPLET |  #     must be skipped
          OBJECT |  #     all content
          STYLE     #     to correspond
        )           #     end tag (3)
      ) |           #   close group (B), or
      ([!/A-Z])     #   one of these chars, remember in (4)
    )               # close group (A)
    (?(4)           # if previous case is (4)
      (?:           #   open group (C)
        (?!         #     and next is not : (D)
          [\s=]     #       \s or "="
          ["`']     #       with open quotest
        )           #     close (D)
        [^>] |      #     and not close tag or
        [\s=]       #     \s or "=" with
        `[^`]*` |   #     something in quotes ` or
        [\s=]       #     \s or "=" with
        '[^']*' |   #     something in quotes ' or
        [\s=]       #     \s or "=" with
        "[^"]*"     #     something in quotes "
      )*            #   repeat (C) 0 or more times
    |               # else (if previous case is not (4))
      .*?           #   minimum of any chars
    )               # end if previous char is (4)
    (?(1)           # if comment (1)
      (?<=--)       #   wait for "--"
    )               # end if comment (1)
    (?(2)           # if another comment (2)
      (?<=\?)       #   wait for "?"
    )               # end if another comment (2)
    (?(3)           # if one of tags-containers (3)
      </            #   wait for end
      (?i:\3)       #   of this tag
      (?:\s[^>]*)?  #   skip junk to ">"
    )               # end if (3)
    >               # tag closed
   }{ }gsxi;    # STRIP THIS TAG

    return $html ? HTML::Entities::decode_entities( $html ) : "";
}

# parse the content for tags that might indicate the story's title
sub html_title($$;$)
{
    my ( $html, $fallback, $trim_to_length ) = @_;

    unless ( defined $html )
    {
        die "HTML is undefined.";
    }

    my $title;

    if ( $html =~ m~<meta property=\"og:title\" content=\"([^\"]+)\"~si )
    {
        $title = $1;
    }
    elsif ( $html =~ m~<meta property=\"og:title\" content=\'([^\']+)\'~si )
    {
        $title = $1;
    }
    elsif ( $html =~ m~<title>(.*?)</title>~si )
    {
        $title = $1;
    }

    if ( $title )
    {

        $title = html_strip( $title );
        $title = trim( $title );
        $title =~ s/\s+/ /g;

        # Moved from _get_medium_title_from_response()
        $title =~ s/^\W*home\W*//i;
    }

    $title = $fallback unless ( $title );

    $title = substr( $title, 0, $trim_to_length ) if ( $trim_to_length && ( length( $title ) > $trim_to_length ) );

    return $title;
}

1;
