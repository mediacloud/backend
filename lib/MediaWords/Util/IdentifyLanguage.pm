package MediaWords::Util::IdentifyLanguage;

use strict;
use warnings;
use utf8;

#
# Utility module to identify a language for a particular text.
#

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;
use Lingua::Identify::CLD;
use MediaWords::Util::Text;

# CLD instance
my $cld = Lingua::Identify::CLD->new();

# Language name -> ISO 690 code mappings
Readonly my %language_names_to_codes => (
    "abkhazian"                            => "ab",
    "afar"                                 => "aa",
    "afrikaans"                            => "af",
    "albanian"                             => "sq",
    "amharic"                              => "am",
    "arabic"                               => "ar",
    "armenian"                             => "hy",
    "assamese"                             => "as",
    "aymara"                               => "ay",
    "azerbaijani"                          => "az",
    "bashkir"                              => "ba",
    "basque"                               => "eu",
    "belarusian"                           => "be",
    "bengali"                              => "bn",
    "bihari"                               => "bh",
    "bislama"                              => "bi",
    "bosnian"                              => "bs",
    "breton"                               => "br",
    "bulgarian"                            => "bg",
    "burmese"                              => "my",
    "catalan"                              => "ca",
    "cherokee"                             => "chr",
    "chinese"                              => "zh",
    "chineset"                             => "zh",
    "corsican"                             => "co",
    "creoles_and_pidgins_english_based"    => "cpe",
    "creoles_and_pidgins_french_based"     => "cpf",
    "creoles_and_pidgins_other"            => "crp",
    "creoles_and_pidgins_portuguese_based" => "cpp",
    "croatian"                             => "hr",
    "czech"                                => "cs",
    "danish"                               => "da",
    "dhivehi"                              => "dv",
    "dutch"                                => "nl",
    "dzongkha"                             => "dz",
    "english"                              => "en",
    "esperanto"                            => "eo",
    "estonian"                             => "et",
    "faroese"                              => "fo",
    "fijian"                               => "fj",
    "finnish"                              => "fi",
    "french"                               => "fr",
    "frisian"                              => "fy",
    "galician"                             => "gl",
    "ganda"                                => "lg",
    "georgian"                             => "ka",
    "german"                               => "de",
    "greek"                                => "el",
    "greenlandic"                          => "kl",
    "guarani"                              => "gn",
    "gujarati"                             => "gu",
    "haitian_creole"                       => "ht",
    "hausa"                                => "ha",
    "hebrew"                               => "he",
    "hindi"                                => "hi",
    "hungarian"                            => "hu",
    "icelandic"                            => "is",
    "indonesian"                           => "id",
    "interlingua"                          => "ia",
    "interlingue"                          => "ie",
    "inuktitut"                            => "iu",
    "inupiak"                              => "ik",
    "irish"                                => "ga",
    "italian"                              => "it",
    "japanese"                             => "ja",
    "javanese"                             => "jw",
    "kannada"                              => "kn",
    "kashmiri"                             => "ks",
    "kazakh"                               => "kk",
    "khasi"                                => "kha",
    "khmer"                                => "km",
    "kinyarwanda"                          => "rw",
    "korean"                               => "ko",
    "kurdish"                              => "ku",
    "kyrgyz"                               => "ky",
    "laothian"                             => "lo",
    "latin"                                => "la",
    "latvian"                              => "lv",
    "limbu"                                => "lif",
    "lingala"                              => "ln",
    "lithuanian"                           => "lt",
    "luxembourgish"                        => "lb",
    "macedonian"                           => "mk",
    "malagasy"                             => "mg",
    "malay"                                => "ms",
    "malayalam"                            => "ml",
    "maltese"                              => "mt",
    "manx"                                 => "gv",
    "maori"                                => "mi",
    "marathi"                              => "mr",
    "moldavian"                            => "mo",
    "mongolian"                            => "mn",
    "montenegrin"                          => "srp",
    "nauru"                                => "na",
    "nepali"                               => "ne",
    "norwegian"                            => "no",    # was "nb" (for Bokmål), changed to generic ISO 690-1 "no"
    "norwegian_n"                          => "nn",
    "occitan"                              => "oc",
    "oriya"                                => "or",
    "oromo"                                => "om",
    "pashto"                               => "ps",
    "persian"                              => "fa",
    "polish"                               => "pl",
    "portuguese"                           => "pt",
    "portuguese_b"                         => "pt",
    "portuguese_p"                         => "pt",
    "punjabi"                              => "pa",
    "quechua"                              => "qu",
    "rhaeto_romance"                       => "rm",
    "romanian"                             => "ro",
    "rundi"                                => "rn",
    "russian"                              => "ru",
    "samoan"                               => "sm",
    "sango"                                => "sg",
    "sanskrit"                             => "sa",
    "scots"                                => "sco",
    "scots_gaelic"                         => "gd",
    "serbian"                              => "sr",
    "serbo_croatian"                       => "sh",
    "sesotho"                              => "st",
    "shona"                                => "sn",
    "sindhi"                               => "sd",
    "sinhalese"                            => "si",
    "siswant"                              => "ss",
    "slovak"                               => "sk",
    "slovenian"                            => "sl",
    "somali"                               => "so",
    "spanish"                              => "es",
    "sundanese"                            => "su",
    "swahili"                              => "sw",
    "swedish"                              => "sv",
    "syriac"                               => "syc",
    "tagalog"                              => "tl",
    "tajik"                                => "tg",
    "tamil"                                => "ta",
    "tatar"                                => "tt",
    "telugu"                               => "te",
    "thai"                                 => "th",
    "tibetan"                              => "bo",
    "tigrinya"                             => "ti",
    "tonga"                                => "to",
    "tsonga"                               => "ts",
    "tswana"                               => "tn",
    "turkish"                              => "tr",
    "turkmen"                              => "tk",
    "twi"                                  => "tw",
    "uighur"                               => "ug",
    "ukrainian"                            => "uk",
    "urdu"                                 => "ur",
    "uzbek"                                => "uz",
    "vietnamese"                           => "vi",
    "volapuk"                              => "vo",
    "welsh"                                => "cy",
    "wolof"                                => "wo",
    "xhosa"                                => "xh",
    "yiddish"                              => "yi",
    "yoruba"                               => "yo",
    "zhuang"                               => "za",
    "zulu"                                 => "zu",
);

# Vice-versa
Readonly my %language_codes_to_names => reverse %language_names_to_codes;

# Min. text length for reliable language identification
Readonly my $RELIABLE_IDENTIFICATION_MIN_TEXT_LENGTH => 10;

# Don't process strings longer than that
Readonly my $MAX_TEXT_LENGTH => 1024 * 1024;

# Returns an ISO 690 language code for the plain text passed as a parameter
# Parameters:
#  * Text that should be identified (required)
#  * Top-level domain that can help with the identification (optional)
#  * True if the content is (X)HTML, false otherwise (optional)
# Returns: ISO 690 language code (e.g. 'en') on successful identification, empty string ('') on failure
sub language_code_for_text($;$$)
{
    my ( $text, $tld, $is_html ) = @_;

    return '' unless ( $text );

    if ( length( $text ) > $MAX_TEXT_LENGTH )
    {
        WARN "Text is longer than $MAX_TEXT_LENGTH, trimming...";
        $text = substr( $text, 0, $MAX_TEXT_LENGTH );
    }

    # Lingua::Identify::CLD doesn't like undef TLDs
    $tld ||= '';

    # We need to verify that the file can cleany encode and decode because CLD
    # can segfault on bad UTF-8
    unless ( MediaWords::Util::Text::is_valid_utf8( $text ) )
    {
        ERROR( "Invalid UTF-8" );
        return '';
    }

    my $language_name =
      lc( $cld->identify( $text, tld => $tld, isPlainText => ( !$is_html ), allowExtendedLanguages => 0 ) );

    if ( $language_name eq 'unknown' or $language_name eq 'tg_unknown_language' or ( !$language_name ) )
    {
        return '';
    }

    unless ( exists( $language_names_to_codes{ $language_name } ) )
    {
        ERROR "Language '$language_name' was identified but is not mapped, please add this language " .
          "to %language_names_to_codes hashmap.";
        return '';
    }

    return $language_names_to_codes{ $language_name };
}

# Returns 1 if the language identification for the text passed as a parameter is likely to be reliable; 0 otherwise
# Parameters:
#  * Text that should be identified (required)
# Returns: 1 if language identification is likely to be reliable; 0 otherwise
sub identification_would_be_reliable($)
{
    my $text = shift;

    unless ( $text )
    {
        return 0;
    }

    # Too short?
    if ( length( $text ) < $RELIABLE_IDENTIFICATION_MIN_TEXT_LENGTH )
    {
        return 0;
    }

    if ( length( $text ) > $MAX_TEXT_LENGTH )
    {
        WARN "Text is longer than $MAX_TEXT_LENGTH, trimming...";
        $text = substr( $text, 0, $MAX_TEXT_LENGTH );
    }

    # We need to verify that the file can cleany encode and decode because CLD
    # can segfault on bad UTF-8
    unless ( MediaWords::Util::Text::is_valid_utf8( $text ) )
    {
        ERROR( "Invalid UTF-8" );
        return '';
    }

    # Not enough letters as opposed to non-letters?
    my $word_character_count = 0;
    my $digit_count          = 0;
    my $underscore_count     = 0;    # Count underscores (_) because \w matches those too

    $word_character_count++ while ( $text =~ m/\w/gu );
    $digit_count++          while ( $text =~ m/\d/g );
    $underscore_count++     while ( $text =~ m/_/g );

    my $letter_count = $word_character_count - $digit_count - $underscore_count;
    if ( $letter_count < $RELIABLE_IDENTIFICATION_MIN_TEXT_LENGTH )
    {
        return 0;
    }

    return 1;
}

# Returns 1 if the language code if supported by the identifier, 0 otherwise
# Parameters:
#  * ISO 639-1 language code
# Returns: 1 if the language can be identified, 0 if it can not
sub language_is_supported($)
{
    my $language_id = shift;

    unless ( $language_id )
    {
        return 0;
    }

    return ( exists $language_codes_to_names{ $language_id } );
}

# return the human readable language name for a given code
sub language_name_for_code($)
{
    my ( $code ) = @_;

    my $name = $language_codes_to_names{ $code };
    return undef unless ( $name );

    $name =~ s/_/ /g;
    $name =~ s/(\w+)/\u\L$1/g;

    return $name;
}

1;
