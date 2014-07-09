package HTML::StripPP;

# pure perl module to strip html from a block of text

# code by powerman from: http://www.perlmonks.org/?node_id=161281

use strict;
use warnings;

use HTML::Entities;

# strip the html tags, html comments, any any text within TITLE, SCRIPT, APPLET, OBJECT, and STYLE tags
sub strip
{
    my ( $html ) = @_;

    if ( !defined( $html ) )
    {
        return undef;
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

1;
