package MediaWords::Languages::no;
use Moose;
with 'MediaWords::Languages::Language';

#
# Norwegian (Bokmål)
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'no';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'no', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'no', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'no', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'no', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # The longest word in Norwegian, that is a real word in ordinary use, is
    # menneskerettighetsorganisasjonene (33 letters).[citation needed] The
    # meaning is "the human rights organizations". Being used mostly in
    # statistics, the term sannsynlighetstetthetsfunksjonene (meaning “the
    # probability density functions”) is also 33 characters long. The physics
    # term minoritetsladningsbærerdiffusjonskoeffisientmålingsapparatur has
    # 60 characters, but is not a common word. Its meaning is "(a) device
    # for measuring the distance between particles in a crystal".
    return 60;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'no',
        'lib/MediaWords/Languages/resources/no_nonbreaking_prefixes.txt', $story_text );
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
    return $self->_get_locale_country_multilingual_object( 'no' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'antigua og barbuda'                 => 'antigua',                        # 'antigua and barbuda'
        'britisk territorium i indiahavet'   => -1,                               # 'british indian ocean territory'
        'de forente arabiske emirater'       => 'arabiske emirater',              # 'united arab emirates'
        'de nederlandske antiller'           => 'nederlandske antiller',          # 'netherlands antilles'
        'de okkuperte palestinske områdene' => 'palestina',                      # 'palestinian territory, occupied'
        'den demokratiske republikken kongo' => 'kongo-kinshasa',                 # 'congo, the democratic republic of the'
        'den dominikanske republikk'         => 'dominikanske republikk',         # 'dominican republic'
        'den sentralafrikanske republikk'    => 'sentralafrikanske republikk',    # 'central african republic'
        'heard- og mcdonald-øyene'          => -1,                               # 'heard island and mcdonald islands'
        'isle of man'                        => -1,                               # 'isle of man'
        'papua ny-guinea'                    => 'papua guinea',                   # 'papua ny-guinea'
        'saint kitts og nevis'               => -1,                               # 'saint kitts and nevis'
        'saint vincent og grenadinene'       => -1,                               # 'saint vincent and the grenadines'
        'saint-martin (franske)'             => -1,                               # 'saint-martin (french part)'
        'saint-pierre-et-miquelon'           => -1,                               # 'saint pierre and miquelon'
        'svalbard og jan mayen'              => -1,                               # 'svalbard and jan mayen'
        'são tomé og príncipe'            => -1,                               # 'sao tome and principe'
        'sør-georgia og de søre sandwichøyene' => -1,                # 'south georgia and the south sandwich islands'
        'søre franske territorier'               => -1,                # 'french southern territories'
        'trinidad og tobago'                      => 'trinidad',        # 'trinidad and tobago'
        'turks- og caicosøyene'                  => -1,                # 'turks and caicos islands'
        'wallis- og futunaøyene'                 => 'futunaøyene',    # 'wallis and futuna'
    };

}

1;
