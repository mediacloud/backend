package MediaWords::Languages::nl;
use Moose;
with 'MediaWords::Languages::Language';

#
# Dutch
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'nl';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'nl', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'nl', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'nl', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'nl', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # Dutch, like many Germanic languages, is capable of forming compounds of potentially limitless
    # length. The 49-letter word Kindercarnavalsoptochtvoorbereidingswerkzaamheden, meaning
    # "preparation activities for a children's carnival procession," was cited by the 1996 Guinness
    # Book of World Records as the longest Dutch word.[2]
    # (http://en.wikipedia.org/wiki/Longest_words#Dutch)
    return 49;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'nl',
        'lib/MediaWords/Languages/resources/nl_nonbreaking_prefixes.txt', $story_text );
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
    return $self->_get_locale_country_multilingual_object( 'nl' );
}

sub get_country_name_remapping
{
    my $self = shift;

    return {
        'amerikaanse kleinere afgelegen eilanden'          => -1,                    # 'united states minor outlying islands'
        'antigua en barbuda'                               => 'antigua',             # 'antigua and barbuda'
        'bosnië en herzegovina'                           => 'bosnië',             # 'bosnia and herzegovina'
        'britse gebieden in de indische oceaan'            => -1,                    # 'british indian ocean territory'
        'centraal-afrikaanse republiek'                    => 'centraal-afrika',     # 'central african republic'
        'franse gebieden in de zuidelijke indische oceaan' => -1,                    # 'french southern territories'
        'heard- en mcdonaldeilanden'                       => -1,                    # 'heard island and mcdonald islands'
        'hongkong sar van china'                           => 'hongkong',            # 'hong kong'
        'isle of man'                                      => -1,                    # 'isle of man'
        'macao sar van china'                              => 'macao',               # 'macao'
        'papoea-nieuw-guinea'                              => 'papoea guinea',       # 'papua new guinea'
        'saint kitts en nevis'                             => -1,                    # 'saint kitts and nevis'
        'saint pierre en miquelon'                         => -1,                    # 'saint pierre and miquelon'
        'saint vincent en de grenadines'                   => -1,                    # 'saint vincent and the grenadines'
        'sao tomé en principe'                            => -1,                    # 'sao tome and principe'
        'svalbard en jan mayen'                            => -1,                    # 'svalbard and jan mayen'
        'trinidad en tobago'                               => 'trinidad',            # 'trinidad and tobago'
        'turks- en caicoseilanden'                         => -1,                    # 'turks and caicos islands'
        'verenigde arabische emiraten'                     => 'arabische emiraten',  # 'united arab emirates'
        'wallis en futuna'                                 => 'futuna',              # 'wallis and futuna'
        'zuid-georgië en zuidelijke sandwicheilanden' => -1,    # 'south georgia and the south sandwich islands'
    };

}

1;
