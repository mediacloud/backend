package MediaWords::Languages::it;
use Moose;
with 'MediaWords::Languages::Language';

#
# Italian
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'it';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'it', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'it', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'it', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'it', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # The longest accepted neologism is psiconeuroendocrinoimmunologia (30 letters).[citation needed]
    # (http://en.wikipedia.org/wiki/Longest_words#Italian)
    return 30;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'it',
        'lib/MediaWords/Languages/resources/it_nonbreaking_prefixes.txt', $story_text );
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
    return $self->_get_locale_country_multilingual_object( 'it' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'antigua e barbuda'                          => 'antigua',           # 'antigua and barbuda'
        'città del vaticano'                        => 'vaticano',          # 'holy see (vatican city state)'
        'corea del nord'                             => 'corea nord',        # 'korea, democratic people\'s republic of'
        'corea del sud'                              => 'corea sud',         # 'korea, republic of'
        'emirati arabi uniti'                        => 'emirati arabi',     # 'united arab emirates'
        'georgia del sud e isole sandwich'           => -1,                  # 'south georgia and the south sandwich islands'
        'isola di man'                               => -1,                  # 'isle of man'
        'isola di natale'                            => -1,                  # 'christmas island'
        'isole fær øer'                            => 'fær øer',         # 'faroe islands'
        'isole heard e mcdonald'                     => -1,                  # 'heard island and mcdonald islands'
        'isole marianne settentrionali'              => -1,                  # 'northern mariana islands'
        'isole minori degli stati uniti'             => -1,                  # 'united states minor outlying islands'
        'isole vergini americane'                    => -1,                  # 'virgin islands, u.s.'
        'isole vergini britanniche'                  => -1,                  # 'virgin islands, british'
        'papua nuova guinea'                         => 'papua guinea',      # 'papua new guinea'
        'rep. dem. del congo'                        => 'congo-kinshasa',    # 'congo, the democratic republic of the'
        'repubblica del congo'                       => 'congo',             # 'congo'
        'saint kitts e nevis'                        => -1,                  # 'saint kitts and nevis'
        'saint vincent e grenadine'                  => -1,                  # 'saint vincent and the grenadines'
        'saint-pierre e miquelon'                    => -1,                  # 'saint pierre and miquelon'
        'stati uniti d\'america'                     => 'stati uniti',       # 'united states'
        'svalbard e jan mayen'                       => -1,                  # 'svalbard and jan mayen'
        'são tomé e príncipe'                     => -1,                  # 'sao tome and principe'
        'territori francesi meridionali'             => -1,                  # 'french southern territories'
        'territorio britannico dell\'oceano indiano' => -1,                  # 'british indian ocean territory'
        'trinidad e tobago'                          => 'trinidad',          # 'trinidad and tobago'
        'turks e caicos'                             => -1,                  # 'turks and caicos islands'
        'wallis e futuna'                            => 'futuna',            # 'wallis and futuna'
    };

}

1;
