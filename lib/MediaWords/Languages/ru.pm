package MediaWords::Languages::ru;
use Moose;
with 'MediaWords::Languages::Language';

#
# Russian
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'ru';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/ru_stoplist_tiny.txt' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/ru_stoplist_short.txt' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->get_short_stop_words();
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'ru', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

# Probably, one of the longest originally-Russian word is превысокомногорассмотрительствующий,
# which contains 35 letters, or its dative case form превысокомногорассмотрительствующему (36
# letters), which can be an example of excessively official vocabulary of XIX century. The
# longest word Numeral compounds, such as Тысячевосьмисотвосьмидесятидевятимикрометровый
# (tysiachevosmisotvosmidesiatideviatimikrometrovyi), which is an adjective containing 46
# letters, means "1889-micrometer".[citation needed]
# (http://en.wikipedia.org/wiki/Longest_words#Russian)
    return 46;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'ru',
        'lib/MediaWords/Languages/resources/ru_nonbreaking_prefixes.txt', $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
