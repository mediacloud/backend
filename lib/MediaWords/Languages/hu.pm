package MediaWords::Languages::hu;
use Moose;
with 'MediaWords::Languages::Language';

#
# Hungarian
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'hu';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'hu', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'hu', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'hu', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'hu', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # Megszentségteleníthetetlenségeskedéseitekért, with 44 letters is officially the longest word in
    # the Hungarian language and means something like "for your [plural] continued behaviour as if
    # you could not be desecrated". It is already morphed, since Hungarian is an agglutinative language.
    # (http://en.wikipedia.org/wiki/Longest_words#Hungarian)
    return 44;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'hu',
        'lib/MediaWords/Languages/resources/hu_nonbreaking_prefixes.txt', $story_text );
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
    return $self->_get_locale_country_multilingual_object( 'hu' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'amerikai csendes-óceáni szigetek'          => -1,                 # 'united states minor outlying islands'
        'amerikai virgin-szigetek'                    => -1,                 # 'virgin islands, u.s.'
        'antigua és barbuda'                         => 'antigua',          # 'antigua and barbuda'
        'brit indiai oceán'                          => -1,                 # 'british indian ocean territory'
        'brit virgin-szigetek'                        => -1,                 # 'virgin islands, british'
        'dél grúzia és a déli szendvics-szigetek' => -1,                 # 'south georgia and the south sandwich islands'
        'egyesült arab emirátus'                    => 'arab emírségek', # 'united arab emirates'
        'francia déli területek'                    => -1,                 # 'french southern territories'
        'heard és mcdonald szigetek'                 => -1,                 # 'heard island and mcdonald islands'
        'hongkong s.a.r, kína'                       => 'hongkong',         # 'hong kong'
        'kókusz (keeling)-szigetek'                  => -1,                 # 'cocos (keeling) islands'
        'közép-afrikai köztársaság'              => 'közép-afrika',   # 'central african republic'
        'macao s.a.r., china'                         => 'macao',            # 'macao'
        'pápua új-guinea'                           => 'pápua guinea',    # 'papua new guinea'
        'saint kitts és nevis'                       => -1,                 # 'saint kitts and nevis'
        'saint pierre és miquelon'                   => -1,                 # 'saint pierre and miquelon'
        'saint vincent és grenadines'                => -1,                 # 'saint vincent and the grenadines'
        'svalbard és jan mayen'                      => -1,                 # 'svalbard and jan mayen'
        'são tomé és príncipe'                    => -1,                 # 'sao tome and principe'
        'trinidad és tobago'                         => 'trinidad',         # 'trinidad and tobago'
        'turks- és caicos-szigetek'                  => -1,                 # 'turks and caicos islands'
        'wallis és futuna'                           => 'futuna',           # 'wallis and futuna'
        'zöld-foki köztársaság'                   => -1,                 # 'cape verde'
        'északi mariana-szigetek'                    => -1,                 # 'northern mariana islands'
    };

}

1;
