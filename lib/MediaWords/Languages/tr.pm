package MediaWords::Languages::tr;
use Moose;
with 'MediaWords::Languages::Language';

#
# Turkish
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'tr';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/tr_stoplist.txt' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/tr_stoplist.txt' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/tr_stoplist.txt' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'tr', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # Muvaffakiyetsizleştiricileştiriveremeyebileceklerimizdenmişsinizcesine, at 70 letters, has been
    # cited as the longest Turkish word, though it is a compound word and Turkish, as an agglutinative
    # language, carries the potential for words of theoretically infinite length.[citation needed]
    return 70;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'tr',
        'lib/MediaWords/Languages/resources/tr_nonbreaking_prefixes.txt', $story_text );
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
    return $self->_get_locale_country_multilingual_object( 'tr' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'abd virgin adaları'          => -1,                       # 'virgin islands, u.s.'
        'amerika birleşik devletleri' => 'birleşik devletler',    # 'united states'
        'amerika birleşik devletleri küçük dış adaları' => -1,           # 'united states minor outlying islands'
        'antigua ve barbuda'                                   => 'antigua',    # 'antigua and barbuda'
        'birleşik arap emirlikleri'                 => 'arap emirlikleri',  # 'united arab emirates'
        'fransız güney bölgeleri'                 => -1,                  # 'french southern territories'
        'güney georgia ve güney sandwich adaları' => -1,                  # 'south georgia and the south sandwich islands'
        'güney kıbrıs rum kesimi'                 => 'kıbrıs',          # 'cyprus'
        'heard adası ve mcdonald adaları'          => -1,                  # 'heard island and mcdonald islands'
        'hint okyanusu i̇ngiliz bölgesi'           => -1,                  # 'british indian ocean territory'
        'hong kong sar - çin'                       => 'hong kong',         # 'hong kong'
        'i̇ngiliz virgin adaları'                  => -1,                  # 'virgin islands, british'
        'kongo demokratik cumhuriyeti'               => 'kongo-kinşasa',    # 'congo, the democratic republic of the'
        'kuzey mariana adaları'                     => -1,                  # 'northern mariana islands'
        'makao s.a.r. çin'                          => 'makao',             # 'macao'
        'mikronezya federal eyaletleri'              => 'mikronezya',        # 'micronesia, federated states of'
        'orta afrika cumhuriyeti'                    => 'orta afrika',       # 'central african republic'
        'papua yeni gine'                            => 'papua gine',        # 'papua new guinea'
        'saint kitts ve nevis'                       => -1,                  # 'saint kitts and nevis'
        'saint pierre ve miquelon'                   => -1,                  # 'saint pierre and miquelon'
        'saint vincent ve grenadinler'               => -1,                  # 'saint vincent and the grenadines'
        'sao tome ve principe'                       => -1,                  # 'sao tome and principe'
        'svalbard ve jan mayen'                      => -1,                  # 'svalbard and jan mayen'
        'trinidad ve tobago'                         => 'trinidad',          # 'trinidad and tobago'
        'turks ve caicos adaları'                   => -1,                  # 'turks and caicos islands'
        'wallis ve futuna'                           => 'futuna',            # 'wallis and futuna'
    };

}

1;
