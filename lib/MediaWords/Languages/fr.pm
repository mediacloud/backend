package MediaWords::Languages::fr;
use Moose;
with 'MediaWords::Languages::Language';

#
# French
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'fr';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'fr', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'fr', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'fr', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'fr', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # The longest usual word in French is anticonstitutionnellement (25 letters), meaning
    # "anticonstitutionally" (in a way which is not conforming to the constitution).[10]
    # (http://en.wikipedia.org/wiki/Longest_words#French)
    return 25;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'fr',
        'lib/MediaWords/Languages/resources/fr_nonbreaking_prefixes.txt', $story_text );
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
    return $self->_get_locale_country_multilingual_object( 'fr' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'afrique du sud'                               => 'afrique sud',     # 'south africa'
        'antigua-et-barbuda'                           => 'antigua',         # 'antigua and barbuda'
        'corée du nord'                               => 'corée nord',     # 'korea, democratic people\'s republic of'
        'corée du sud'                                => 'corée sud',      # 'korea, republic of'
        'côte d’ivoire'                             => 'côte d\'ivoire', # 'cote d\'ivoire' (different apostrophe)
        'géorgie du sud et les îles sandwich du sud' => -1,                # 'south georgia and the south sandwich islands'
        'papouasie-nouvelle-guinée'                 => 'papouasie guinée', # 'papua new guinea'
        'r.a.s. chinoise de hong kong'               => 'hong kong',         # 'hong kong'
        'r.a.s. chinoise de macao'                   => 'macao',             # 'macao'
        'république démocratique du congo'         => 'congo-kinshasa',    # 'congo, the democratic republic of the'
        'saint-kitts-et-nevis'                       => -1,                  # 'saint kitts and nevis'
        'saint-pierre-et-miquelon'                   => -1,                  # 'saint pierre and miquelon'
        'saint-vincent-et-les grenadines'            => -1,                  # 'saint vincent and the grenadines'
        'sao tomé-et-principe'                      => -1,                  # 'sao tome and principe'
        'svalbard et île jan mayen'                 => -1,                  # 'svalbard and jan mayen'
        'terres australes françaises'               => -1,                  # 'french southern territories'
        'territoire britannique de l\'océan indien' => -1,                  # 'british indian ocean territory'
        'trinité-et-tobago'                         => 'trinité-tobago',   # 'trinidad and tobago'
        'wallis-et-futuna'                           => 'futuna',            # 'wallis and futuna'
        'émirats arabes unis'                       => 'émirats arabes',   # 'united arab emirates'
        'état de la cité du vatican'               => 'vatican',           # 'holy see (vatican city state)'
        'états fédérés de micronésie'           => 'micronésie',       # 'micronesia, federated states of'
        'île de man'                                => -1,                  # 'isle of man'
        'îles des cocos (keeling)'                  => -1,                  # 'cocos (keeling) islands'
        'îles heard et macdonald'                   => -1,                  # 'heard island and mcdonald islands'
        'îles mariannes du nord'                    => -1,                  # 'northern mariana islands'
        'îles mineures éloignées des états-unis' => -1,                  # 'united states minor outlying islands'
        'îles turks et caïques'                    => -1,                  # 'turks and caicos islands'
        'îles vierges britanniques'                 => -1,                  # 'virgin islands, british'
        'îles vierges des états-unis'              => -1,                  # 'virgin islands, u.s.'
    };

}

1;
