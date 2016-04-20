package MediaWords::Languages::es;
use Moose;
with 'MediaWords::Languages::Language';

#
# Spanish
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'es';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'es', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'es', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'es', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'es', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # The adverb superextraordinarísimamente (superextraordinarily) (Spanish pronunciation:
    # [supeɾekstɾaorðinaˈɾisimaˈmente]) at 27 letters, is often considered to be the longest
    # in the Spanish language.[1][2] However, the status of this word has been challenged
    # for lack of popular use. The 24-letter word electroencefalografistas
    # (electroencephalographists) has been cited as the longest Spanish word in actual use.[1]
    # The 23-letter words esternocleidomastoideo (sternocleidomastoid) and
    # anticonstitucionalmente (unconstitionally) are two of the longest words in the Spanish
    # language, though the latter was removed from the Real Academia Española's dictionary
    # in 2005.
    # (http://en.wikipedia.org/wiki/Longest_word_in_Spanish)
    return 27;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'es',
        'lib/MediaWords/Languages/resources/es_nonbreaking_prefixes.txt', $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
