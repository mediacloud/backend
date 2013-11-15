package MediaWords::Languages::es;
use Moose;
with 'MediaWords::Languages::Language';

#
# Spanish
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'es';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'es', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'es', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'es', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'es', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # The adverb superextraordinarísimamente (superextraordinarily) (Spanish pronunciation:
    # [supeɾekstɾaorðinaˈɾisimaˈmente]) at 27 letters, is often considered to be the longest
    # in the Spanish language.[1][2] However, the status of this word has been challenged
    # for lack of popular use. The 24-letter word electroencefalografistas
    # (electroencephalographists) has been cited as the longest Spanish word in actual use.[1]
    # The 23-letter words esternocleidomastoideo (sternocleidomastoid) and
    # anticonstitucionalmente (unconstitionally) are two of the longest words in the Spanish
    # language, though the latter was removed from the Real Academia Española's dictionary
    # in 2005.
    # (http://en.wikipedia.org/wiki/Longest_word_in_Spanish)
    return 27;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'es',
        'lib/MediaWords/Languages/resources/es_nonbreaking_prefixes.txt', $story_text );
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
    return $self->_get_locale_country_multilingual_object( 'es' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'antigua y barbuda'                         => 'antigua',            # 'antigua and barbuda'
        'bosnia y herzegovina'                      => 'bosnia',             # 'bosnia and herzegovina'
        'ciudad del vaticano'                       => 'vaticano',           # 'holy see (vatican city state)'
        'corea del norte'                           => 'norcorea',           # 'korea, democratic people\'s republic of'
        'corea del sur'                             => 'surcorea',           # 'korea, republic of'
        'costa de marfil'                           => 'cote d\'ivoire',     # 'cote d\'ivoire'
        'emiratos árabes unidos'                   => 'emiratos árabes',   # 'united arab emirates'
        'isla de man'                               => -1,                   # 'isle of man'
        'isla de navidad'                           => -1,                   # 'christmas island'
        'islas georgias del sur y sandwich del sur' => -1,                   # 'south georgia and the south sandwich islands'
        'islas heard y mcdonald'                    => -1,                   # 'heard island and mcdonald islands'
        'islas marianas del norte'                  => -1,                   # 'northern mariana islands'
        'islas turcas y caicos'                     => -1,                   # 'turks and caicos islands'
        'islas ultramarinas de estados unidos'      => -1,                   # 'united states minor outlying islands'
        'islas vírgenes británicas'               => -1,                   # 'virgin islands, british'
        'islas vírgenes estadounidenses'           => -1,                   # 'virgin islands, u.s.'
        'papúa nueva guinea'                       => 'papua guinea',       # 'papua new guinea'
        'república de china'                       => 'taiwán',            # 'taiwan, province of china'
        'república del congo'                      => 'congo brazzaville',  # 'congo'
        'república democrática del congo'         => 'congo democrático', # 'congo, the democratic republic of the'
        'san cristóbal y nieves'                   => -1,                   # 'saint kitts and nevis'
        'san pedro y miquelón'                     => -1,                   # 'saint pierre and miquelon'
        'san vicente y las granadinas'              => -1,                   # 'saint vincent and the grenadines'
        'santo tomé y príncipe'                   => -1,                   # 'sao tome and principe'
        'svalbard y jan mayen'                      => -1,                   # 'svalbard and jan mayen'
        'territorio británico del océano índico' => -1,                   # 'british indian ocean territory'
        'territorios australes franceses'           => -1,                   # 'french southern territories'
        'trinidad y tobago'                         => 'trinidad',           # 'trinidad and tobago'
        'wallis y futuna'                           => 'futuna',             # 'wallis and futuna'
    };

}

1;
