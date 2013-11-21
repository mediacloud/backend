package MediaWords::Languages::da;
use Moose;
with 'MediaWords::Languages::Language';

#
# Danish
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'da';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'da', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'da', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'da', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'da', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # Speciallægepraksisplanlægningsstabiliseringsperiode, which is 51 letters, is the longest Danish
    # word that has been used in an official context. It means "Period of plan stabilising for a
    # specialist doctor's practice," and was used during negotiations with the local government.[citation needed]
    # Konstantinopolitanerinde, meaning female inhabitant of Constantinople, is often mentioned as the
    # longest non-compound word.[citation needed]
    # (http://en.wikipedia.org/wiki/Longest_words#Danish)
    return 51;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'da',
        'lib/MediaWords/Languages/resources/da_nonbreaking_prefixes.txt', $story_text );
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
    return $self->_get_locale_country_multilingual_object( 'da' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'antigua og barbuda'                              => 'antigua',              # 'antigua and barbuda'
        'de britiske jomfruøer'                          => -1,                     # 'virgin islands, british'
        'de amerikanske jomfruøer'                       => -1,                     # 'virgin islands, u.s.'
        'de mindre amerikanske oversøiske øer'          => -1,                     # 'united states minor outlying islands'
        'de palæstinensiske områder'                    => 'palæstina',           # 'palestinian territory, occupied'
        'den dominikanske republik'                       => 'dominikanske',         # 'dominican republic'
        'det britiske territorium i det indiske ocean'    => -1,                     # 'british indian ocean territory'
        'forenede arabiske emirater'                      => 'emirater arabiske',    # 'united arab emirates'
        'franske besiddelser i det sydlige indiske ocean' => -1,                     # 'french indian ocean territory'
        'heard- og mcdonald-øerne'                       => -1,                     # 'heard island and mcdonald islands'
        'isle of man'                                     => -1,                     # 'isle of man'
        'mikronesiens forenede stater'                    => 'mikronesien',          # 'micronesia, federated states of'
        'papua ny guinea'                                 => 'papua guinea',         # 'papua new guinea'
        'saint kitts og nevis'                            => -1,                     # 'saint kitts and nevis'
        'saint pierre og miquelon'                        => -1,                     # 'saint pierre and miquelon'
        'south georgia og de sydlige sandwichøer' => -1,                # 'south georgia and the south sandwich islands'
        'st. vincent og grenadinerne'              => -1,                # 'saint vincent and the grenadines'
        'svalbard og jan mayen'                    => -1,                # 'svalbard and jan mayen'
        'são tomé og príncipe'                  => -1,                # 'sao tome and principe'
        'trinidad og tobago'                       => 'trinidad',        # 'trinidad and tobago'
        'turks- og caicosøerne'                   => -1,                # 'turks and caicos islands'
        'wallis og futunaøerne'                   => 'futunaøerne',    # 'wallis and futuna'
    };

}

1;
