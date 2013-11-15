package MediaWords::Languages::ru;
use Moose;
with 'MediaWords::Languages::Language';

#
# Russian
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'ru';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/ru_stoplist_tiny.txt' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/ru_stoplist_short.txt' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->get_short_stop_words();
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'ru', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

# Probably, one of the longest originally-Russian word is превысокомногорассмотрительствующий,
# which contains 35 letters, or its dative case form превысокомногорассмотрительствующему (36
# letters), which can be an example of excessively official vocabulary of XIX century. The
# longest word Numeral compounds, such as Тысячевосьмисотвосьмидесятидевятимикрометровый
# (tysiachevosmisotvosmidesiatideviatimikrometrovyi), which is an adjective containing 46
# letters, means "1889-micrometer".[citation needed]
# (http://en.wikipedia.org/wiki/Longest_words#Russian)
    return 46;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'ru',
        'lib/MediaWords/Languages/resources/ru_nonbreaking_prefixes.txt', $story_text );
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
    return $self->_get_locale_country_multilingual_object( 'ru' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'американские виргинские острова' => -1,                  # 'virgin islands, u.s.'
        'антигуа и барбуда'                             => 'антигуа',    # 'antigua and barbuda'
        'босния и герцеговина'                       => 'босния',      # 'bosnia and herzegovina'
        'британская территория в индийском океане' =>
          -1,    # 'british indian ocean territory'
        'британские виргинские острова' => -1,    # 'virgin islands, british'
        'внешние малые острова (сша)'        => -1,    # 'united states minor outlying islands'
        'демократическая республика конго' =>
          'конго-киншаса',                                       # 'congo, the democratic republic of the'
        'корейская народно-демократическая республика' =>
          'северная корея',                                     # 'korea, democratic people\'s republic of'
        'кот д’ивуар' => 'кот д\'ивуар',                 # 'cote d\'ivoire' (different apostrophe)
        'нидерландские антильские острова' => -1,    # 'netherlands antilles'
        'объединенные арабские эмираты' =>
          'арабские эмираты',                                       # 'united arab emirates'
        'остров святого бартоломея' => -1,    # 'saint barthelemy'
        'остров святого мартина'       => -1,    # 'saint-martin (french part)'
        'остров святой елены'             => -1,    # 'saint helena, ascension and tristan da cunha'
        'острова зеленого мыса'        => 'кабо-верде',     # 'cape verde'
        'острова тёркс и кайкос'       => -1,                        # 'turks and caicos islands'
        'острова херд и макдональд' => -1,                        # 'heard island and mcdonald islands'
        'папуа-новая гвинея'              => 'папуа гвинея', # 'papua new guinea'
        'сан-томе и принсипи'             => -1,                        # 'sao tome and principe'
        'свальбард и ян-майен'           => -1,                        # 'svalbard and jan mayen'
        'северные марианские острова'     => -1,               # 'northern mariana islands'
        'сен-пьер и микелон'                        => -1,               # 'saint pierre and miquelon'
        'сент-винсент и гренадины'            => -1,               # 'saint vincent and the grenadines'
        'сент-киттс и невис'                        => -1,               # 'saint kitts and nevis'
        'сирийская арабская республика' => 'сирия',     # 'syrian arab republic'
        'тринидад и тобаго' => 'тринидад',                       # 'trinidad and tobago'
        'уоллис и футуна'     => 'футуна',                           # 'wallis and futuna'
        'федеративные штаты микронезии' =>
          'микронезия',                                                       # 'micronesia, federated states of'
        'французские южные территории' => -1,                 # 'french southern territories'
        'центрально-африканская республика' =>
          'центральная африка',                                        # 'central african republic'
        'южная джорджия и южные сандвичевы острова' =>
          -1,    # 'south georgia and the south sandwich islands'
    };

}

1;
