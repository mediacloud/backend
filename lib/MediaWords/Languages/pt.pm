package MediaWords::Languages::pt;
use Moose;
with 'MediaWords::Languages::Language';

#
# Portuguese
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'pt';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'pt', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'pt', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'pt', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'pt', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # The 46-letter word pneumoultramicroscopicossilicovulcanoconioticozinhos
    # (plural diminutive of pneumoultramicroscopicossilicovulcanoconiótico) is
    # the longest word[citation needed]. It is an adjective referring to a
    # sufferer of the disease pneumonoultramicroscopicsilicovolcanoconiosis.
    # The 29-letter word anticonstitucionalissimamente (adverb, meaning "in a
    # very unconstitutional way") is recognized as being the longest
    # non-technical word.[citation needed]
    # (http://en.wikipedia.org/wiki/Longest_words#Portuguese)
    return 46;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'pt',
        'lib/MediaWords/Languages/resources/pt_nonbreaking_prefixes.txt', $story_text );
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
    return $self->_get_locale_country_multilingual_object( 'pt' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'antígua e barbuda'                          => 'antígua',         # 'antigua and barbuda'
        'bósnia e herzegovina'                       => 'bósnia',          # 'bosnia and herzegovina'
        'coreia do sul'                               => 'coreia sul',       # 'korea, republic of'
        'costa do marfim'                             => 'costa marfim',     # 'cote d\'ivoire'
        'emirados árabes unidos'                     => 'emirados árabes', # 'united arab emirates'
        'estados unidos da américa'                  => 'estados unidos',   # 'united states'
        'geórgia do sul e sandwich do sul, ilhas'    => -1,                 # 'south georgia and the south sandwich islands'
        'heard e ilhas mcdonald, ilha'                => -1,                 # 'heard island and mcdonald islands'
        'menores distantes dos estados unidos, ilhas' => -1,                 # 'united states minor outlying islands'
        'myanmar (antiga birmânia)'                  => 'myanmar',          # 'myanmar'
        'nova zelândia (aotearoa)'                   => 'nova zelândia',   # 'new zealand'
        'papua-nova guiné'                           => 'papua guiné',     # 'papua new guinea'
        'países baixos (holanda)'                    => 'holanda',          # 'netherlands'
        'reino unido da grã-bretanha e irlanda do norte' =>
          -1,    # 'United Kingdom of Great Britain and Ireland' (former name of UK)
        'saint pierre et miquelon'                        => -1,               # 'saint pierre and miquelon'
        'samoa (samoa ocidental)'                         => 'samoa',          # 'samoa'
        'svalbard e jan mayen'                            => -1,               # 'svalbard and jan mayen'
        'são cristóvão e névis (saint kitts e nevis)' => -1,               # 'saint kitts and nevis'
        'são tomé e príncipe'                          => -1,               # 'sao tome and principe'
        'são vicente e granadinas'                       => -1,               # 'saint vincent and the grenadines'
        'terras austrais e antárticas francesas (taaf)'  => -1,               # 'french southern territories'
        'território britânico do oceano índico'        => -1,               # 'british indian ocean territory'
        'trindade e tobago'                               => 'trindade',       # 'trinidad and tobago'
        'turks e caicos'                                  => -1,               # 'turks and caicos islands'
        'wallis e futuna'                                 => 'futuna',         # 'wallis e futuna'
        'áfrica do sul'                                  => 'áfrica sul',    # 'south africa'
    };

}

1;
