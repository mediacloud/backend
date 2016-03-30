package MediaWords::Util::IdentifyLanguage;

#
# Utility module to identify a language for a particular text.
#
# How to use:
#  1) Download compact-language-detector_0.1-1_amd64.deb from:
#         http://code.google.com/p/chromium-compact-language-detector/downloads/list
#  2) dpkg -i compact-language-detector_0.1-1_amd64.deb
#  3) ./script/run_carton.sh install Lingua::Identify::CLD
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use utf8;

use Lingua::Identify::CLD;

# URL -> TLD
use Domain::PublicSuffix;
use URI;

use Readonly;

{

    # CLD instance
    my $cld = Lingua::Identify::CLD->new();

    # Domain::PublicSuffix instance
    my $dps = Domain::PublicSuffix->new();

    # Language name -> ISO 690 code mappings
    my Readonly %language_names_to_codes = (
        "english"                              => "en",
        "danish"                               => "da",
        "dutch"                                => "nl",
        "finnish"                              => "fi",
        "french"                               => "fr",
        "german"                               => "de",
        "hebrew"                               => "he",
        "italian"                              => "it",
        "japanese"                             => "ja",
        "korean"                               => "ko",
        "norwegian"                            => "no",    # was "nb" (for Bokmål), changed to generic ISO 690-1 "no"
        "polish"                               => "pl",
        "portuguese"                           => "pt",
        "russian"                              => "ru",
        "spanish"                              => "es",
        "swedish"                              => "sv",
        "chinese"                              => "zh",
        "czech"                                => "cs",
        "greek"                                => "el",
        "icelandic"                            => "is",
        "latvian"                              => "lv",
        "lithuanian"                           => "lt",
        "romanian"                             => "ro",
        "hungarian"                            => "hu",
        "estonian"                             => "et",
        "bulgarian"                            => "bg",
        "croatian"                             => "hr",
        "serbian"                              => "sr",
        "irish"                                => "ga",
        "galician"                             => "gl",
        "tagalog"                              => "tl",
        "turkish"                              => "tr",
        "ukrainian"                            => "uk",
        "hindi"                                => "hi",
        "macedonian"                           => "mk",
        "bengali"                              => "bn",
        "indonesian"                           => "id",
        "latin"                                => "la",
        "malay"                                => "ms",
        "malayalam"                            => "ml",
        "welsh"                                => "cy",
        "nepali"                               => "ne",
        "telugu"                               => "te",
        "albanian"                             => "sq",
        "tamil"                                => "ta",
        "belarusian"                           => "be",
        "javanese"                             => "jw",
        "occitan"                              => "oc",
        "urdu"                                 => "ur",
        "bihari"                               => "bh",
        "gujarati"                             => "gu",
        "thai"                                 => "th",
        "arabic"                               => "ar",
        "catalan"                              => "ca",
        "esperanto"                            => "eo",
        "basque"                               => "eu",
        "interlingua"                          => "ia",
        "kannada"                              => "kn",
        "punjabi"                              => "pa",
        "scots_gaelic"                         => "gd",
        "swahili"                              => "sw",
        "slovenian"                            => "sl",
        "marathi"                              => "mr",
        "maltese"                              => "mt",
        "vietnamese"                           => "vi",
        "frisian"                              => "fy",
        "slovak"                               => "sk",
        "chineset"                             => "zh",
        "faroese"                              => "fo",
        "sundanese"                            => "su",
        "uzbek"                                => "uz",
        "amharic"                              => "am",
        "azerbaijani"                          => "az",
        "georgian"                             => "ka",
        "tigrinya"                             => "ti",
        "persian"                              => "fa",
        "bosnian"                              => "bs",
        "sinhalese"                            => "si",
        "norwegian_n"                          => "nn",
        "portuguese_p"                         => "pt",
        "portuguese_b"                         => "pt",
        "xhosa"                                => "xh",
        "zulu"                                 => "zu",
        "guarani"                              => "gn",
        "sesotho"                              => "st",
        "turkmen"                              => "tk",
        "kyrgyz"                               => "ky",
        "breton"                               => "br",
        "twi"                                  => "tw",
        "yiddish"                              => "yi",
        "serbo_croatian"                       => "sh",
        "somali"                               => "so",
        "uighur"                               => "ug",
        "kurdish"                              => "ku",
        "mongolian"                            => "mn",
        "armenian"                             => "hy",
        "laothian"                             => "lo",
        "sindhi"                               => "sd",
        "rhaeto_romance"                       => "rm",
        "afrikaans"                            => "af",
        "luxembourgish"                        => "lb",
        "burmese"                              => "my",
        "khmer"                                => "km",
        "tibetan"                              => "bo",
        "dhivehi"                              => "dv",
        "cherokee"                             => "chr",
        "syriac"                               => "syc",
        "limbu"                                => "lif",
        "oriya"                                => "or",
        "assamese"                             => "as",
        "corsican"                             => "co",
        "interlingue"                          => "ie",
        "kazakh"                               => "kk",
        "lingala"                              => "ln",
        "moldavian"                            => "mo",
        "pashto"                               => "ps",
        "quechua"                              => "qu",
        "shona"                                => "sn",
        "tajik"                                => "tg",
        "tatar"                                => "tt",
        "tonga"                                => "to",
        "yoruba"                               => "yo",
        "creoles_and_pidgins_english_based"    => "cpe",
        "creoles_and_pidgins_french_based"     => "cpf",
        "creoles_and_pidgins_portuguese_based" => "cpp",
        "creoles_and_pidgins_other"            => "crp",
        "maori"                                => "mi",
        "wolof"                                => "wo",
        "abkhazian"                            => "ab",
        "afar"                                 => "aa",
        "aymara"                               => "ay",
        "bashkir"                              => "ba",
        "bislama"                              => "bi",
        "dzongkha"                             => "dz",
        "fijian"                               => "fj",
        "greenlandic"                          => "kl",
        "hausa"                                => "ha",
        "haitian_creole"                       => "ht",
        "inupiak"                              => "ik",
        "inuktitut"                            => "iu",
        "kashmiri"                             => "ks",
        "kinyarwanda"                          => "rw",
        "malagasy"                             => "mg",
        "nauru"                                => "na",
        "oromo"                                => "om",
        "rundi"                                => "rn",
        "samoan"                               => "sm",
        "sango"                                => "sg",
        "sanskrit"                             => "sa",
        "siswant"                              => "ss",
        "tsonga"                               => "ts",
        "tswana"                               => "tn",
        "volapuk"                              => "vo",
        "zhuang"                               => "za",
        "khasi"                                => "kha",
        "scots"                                => "sco",
        "ganda"                                => "lg",
        "manx"                                 => "gv",
        "montenegrin"                          => "srp"
    );

    # Vice-versa
    my Readonly %language_codes_to_names = reverse %language_names_to_codes;

    # Returns an ISO 690 language code for the plain text passed as a parameter
    # Parameters:
    #  * Text that should be identified (required)
    #  * Top-level domain that can help with the identification (optional)
    #  * True if the content is (X)HTML, false otherwise (optional)
    # Returns: ISO 690 language code (e.g. 'en') on successful identification, empty string ('') on failure
    sub language_code_for_text($;$$)
    {
        my ( $text, $tld, $is_html ) = @_;

        $is_html = $is_html ? 1 : 0;

        my $language_name;

        if ( defined $tld and $tld )
        {
            $tld = lc( $tld );
            $language_name = $cld->identify( $text, tld => $tld, isPlainText => ( !$is_html ), allowExtendedLanguages => 0 );
        }
        else
        {
            $language_name = $cld->identify( $text, isPlainText => ( !$is_html ), allowExtendedLanguages => 0 );
        }

        $language_name = lc( $language_name );

        my $language_id = '';
        if ( $language_name eq 'unknown' || $language_name eq 'tg_unknown_language' || ( !$language_name ) )
        {

            # Oh well.
            return '';

        }

        unless ( exists( $language_names_to_codes{ $language_name } ) )
        {
            say STDERR "Language '$language_name' was identified but is not mapped, please add this language " .
              "to %language_names_to_codes hashmap.\n";
            return '';
        }

        return $language_names_to_codes{ $language_name };
    }

    # # Returns an ISO 690 language code for the plain text passed as a parameter
    # # Parameters:
    # #  * Text that should be identified (required)
    # #  * Top-level domain that can help with the identification (optional)
    # #  * True if the content is (X)HTML, false otherwise (optional)
    # # Returns: ISO 690 language code (e.g. 'en') on successful identification, empty string ('') on failure
    # sub language_code_for_text_and_url($;$$)
    # {
    # 	my ( $text, $url, $tld, $is_html ) = @_;

    # 	my $story_tld = '';

    # 	if ( defined( $url ) )
    # 	{
    # 	    my $story_url = $story->{ url };
    # 	    my $story_tld = MediaWords::Util::IdentifyLanguage::tld_from_url( $story_url );
    # 	}
    # else
    # {
    #     say STDERR "Story's URL for story ID " . $story->{ stories_id } . " is not defined.";
    # }

    # }

    # Returns 1 if the language identification for the text passed as a parameter is likely to be reliable; 0 otherwise
    # Parameters:
    #  * Text that should be identified (required)
    # Returns: 1 if language identification is likely to be reliable; 0 otherwise
    sub identification_would_be_reliable($)
    {
        my $text = shift;

        # No text at all?
        if ( !$text )
        {
            return 0;
        }

        # Too short?
        if ( length( $text ) < 10 )
        {
            return 0;
        }

        # Not enough letters as opposed to non-letters?
        my $letter_count     = 0;
        my $underscore_count = 0;    # Count underscores (_) because \w matches those too
        $letter_count++ while ( $text =~ m/\w/g );      # 'use utf8' ensures that UTF-8 characters are matched correctly
        $underscore_count++ while ( $text =~ m/_/g );
        if ( ( $letter_count - $underscore_count ) < 10 )
        {
            return 0;
        }

        return 1;
    }

    # Returns TLD (top-level domain) of the URL passed as a parameter
    # (http://stackoverflow.com/q/8031620/200603)
    # Parameters:
    #  * URL
    # Returns: TLD of the URL or empty string in case of an error
    sub tld_from_url($)
    {
        my $url = shift;

        # Treat relative URLs as absolute URLs with missing http://.
        $url = "http://$url" if $url !~ /^\w+:/;

        my $host;

        eval {
            $host = URI->new( $url )->host();
            $host =~ s/\.\z//;    # D::PS doesn't handle "domain.com.".
        };
        return '' if ( $@ );

        if ( !$dps->get_root_domain( $host ) )
        {

            # say STDERR "Unable to get root domain for host '$host'.";
            return '';
        }

        return $dps->tld();
    }

    # Returns 1 if the language code if supported by the identifier, 0 otherwise
    # Parameters:
    #  * ISO 639-1 language code
    # Returns: 1 if the language can be identified, 0 if it can not
    sub language_is_supported($)
    {
        my $language_id = shift;

        if ( exists $language_codes_to_names{ $language_id } )
        {
            return 1;
        }
        else
        {
            return 0;
        }
    }

}

1;
