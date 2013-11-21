package MediaWords::Languages::fi;
use Moose;
with 'MediaWords::Languages::Language';

#
# Finnish
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'fi';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'fi', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'fi', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'fi', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'fi', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # An example of an actually long word that has been used in the Finnish language is
    # kolmivaihekilowattituntimittari which means "three phase kilowatt hour meter"
    # (31 letters) or lentokonesuihkuturbiinimoottoriapumekaanikkoaliupseerioppilas
    # "airplane jet turbine engine auxiliary mechanic under officer student" (61 letters)
    # which has been deprecated. If conjugation is allowed even longer real words can be
    # made. Allowing derivatives and clitic allows the already lengthy word to grow even
    # longer even though the real usability of the word starts to degrade. The Finnish
    # language uses free forming of composite words: New words can even be formed during
    # a conversation. This allows for adding nouns after each other without breaking
    # grammar rules.
    return 61;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'fi',
        'lib/MediaWords/Languages/resources/fi_nonbreaking_prefixes.txt', $story_text );
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
    return $self->_get_locale_country_multilingual_object( 'fi' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'antigua ja barbuda'                          => 'antigua',          # 'antigua and barbuda'
        'bosnia ja hertsegovina'                      => 'bosnia',           # 'bosnia and herzegovina'
        'brittiläinen intian valtameren alue'        => -1,                 # 'british indian ocean territory'
        'etelä-georgia ja eteläiset sandwichsaaret' => -1,                 # 'south georgia and the south sandwich islands'
        'heard- ja mcdonaldinsaaret'                  => -1,                 # 'heard island and mcdonald islands'
        'hongkong – kiinan erityishallintoalue'     => 'hongkong',         # 'hong kong'
        'huippuvuoret ja jan mayen'                   => -1,                 # 'svalbard and jan mayen'
        'keski-afrikan tasavalta'                     => 'keski-afrikan',    # 'central african republic'
        'macao – kiinan erityishallintoalue'        => 'macao',            # 'macao',
        'papua-uusi-guinea'                           => 'papua-guinea',     # 'papua new guinea'
        'ranskan ulkopuoliset eteläiset alueet'      => -1,                 # 'french southern territories'
        'saint kitts ja nevis'                        => -1,                 # 'saint kitts and nevis'
        'saint vincent ja grenadiinit'                => -1,                 # 'saint vincent and the grenadines'
        'saint-pierre ja miquelon'                    => -1,                 # 'saint pierre and miquelon'
        'são tomé ja príncipe'                     => -1,                 # 'sao tome and principe'
        'trinidad ja tobago'                          => 'trinidad',         # 'trinidad and tobago'
        'turks- ja caicossaaret'                      => -1,                 # 'turks and caicos islands'
        'wallis ja futuna'                            => 'futuna',           # 'wallis and futuna'
        'yhdysvaltain pienet erillissaaret'           => -1,                 # 'united states minor outlying islands'
    };

}

1;
