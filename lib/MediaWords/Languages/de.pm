package MediaWords::Languages::de;
use Moose;
with 'MediaWords::Languages::Language';

#
# German
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'de';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'de', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'de', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'de', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'de', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # In German, whole numbers (smaller than 1 million) are expressed as single words,
    # which makes siebenhundertsiebenundsiebzigtausendsiebenhundertsiebenundsiebzig
    # (777,777) a 65 letter word. In combination with -fach or, as a noun, (das ...)
    # -fache, all numbers are written as one word. A 79 letter word,
    # Donaudampfschifffahrtselektrizitätenhauptbetriebswerkbauunterbeamtengesellschaft,
    # was named the longest published word in the German language by the 1996 Guinness
    # Book of World Records, but longer words are possible. The word refers to a
    # division of an Austrian steam-powered shipping company named the
    # Donaudampfschiffahrtsgesellschaft which transported passengers and cargo on the
    # Danube. The longest word that is not created artificially as a longest-word
    # record seems to be Rindfleischetikettierungsüberwachungsaufgabenübertragungsgesetz
    # at 63 letters.
    # (http://en.wikipedia.org/wiki/Longest_words#German)

    return 79;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'de',
        'lib/MediaWords/Languages/resources/de_nonbreaking_prefixes.txt', $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

sub get_noise_strings
{
    my $self          = shift;
    my @noise_strings = (

        # FIXME add language-dependent noise strings (see en.pm for example)
    );
    return \@noise_strings;
}

sub get_copyright_strings
{
    my $self              = shift;
    my @copyright_strings = (

        # FIXME add language-dependent copyright strings (see en.pm for example)
        'copyright',
        'copying',
        '&copy;',
        'all rights reserved',
    );
    return \@copyright_strings;
}

sub get_locale_codes_api_object
{
    my $self = shift;
    return $self->_get_locale_country_multilingual_object( 'de' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'antigua und barbuda'                            => 'antigua',     # 'antigua and barbuda'
        'bosnien und herzegowina'                        => 'bosnien',     # 'bosnia and herzegovina'
        'britisches territorium im indischen ozean'      => -1,            # 'britisches territorium im indischen ozean'
        'französische süd- und antarktisgebiete'       => -1,            # 'french southern territories'
        'heard- und mcdonald-inseln'                     => -1,            # 'heard island and mcdonald islands'
        'libysch-arabische dschamahirija (libyen)'       => 'libyen',      # 'libyan arab jamahiriya'
        'republik china (taiwan)'                        => 'taiwan',      # 'taiwan, province of china'
        'saint-martin (franz. teil)'                     => -1,            # 'saint-martin (french part)'
        'saint-pierre und miquelon'                      => -1,            # 'saint pierre and miquelon'
        'st. kitts und nevis'                            => -1,            # 'saint kitts and nevis'
        'st. vincent und die grenadinen'                 => -1,            # 'saint vincent and the grenadines'
        'svalbard und jan mayen'                         => -1,            # 'svalbard and jan mayen'
        'são tomé und príncipe'                       => -1,            # 'sao tome and principe'
        'südgeorgien und die südlichen sandwichinseln' => -1,            # 'south georgia and the south sandwich islands'
        'trinidad und tobago'                            => 'trinidad',    # 'trinidad and tobago'
        'turks- und caicosinseln'                        => -1,            # 'turks and caicos islands'
        'united states minor outlying islands'           => -1,            # 'united states minor outlying islands'
        'vereinigte arabische emirate'                           => 'emirate arabische',         # 'united arab emirates'
        'vereinigte staaten von amerika'                         => 'vereinigte staaten',        # 'united states of america'
        'vereinigtes königreich großbritannien und nordirland' => 'vereinigtes königreich',   # 'united kingdom'
        'wallis und futuna'                                      => 'futuna',                    # 'wallis and futuna'
    };

}

1;
