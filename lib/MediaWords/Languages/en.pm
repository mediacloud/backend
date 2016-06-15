package MediaWords::Languages::en;
use Moose;
with 'MediaWords::Languages::Language';

#
# English
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'en';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'en', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/en_stoplist_short.txt' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/en_stoplist_long.txt' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'en', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # The 45-letter word pneumonoultramicroscopicsilicovolcanoconiosis is the longest English word
    # that appears in a major dictionary.[6] Originally coined to become a candidate for the longest
    # word in English, the term eventually developed some independent use in medicine.[7] It is
    # referred to as "P45" by researchers.[8]
    # (http://en.wikipedia.org/wiki/Longest_words#English)
    return 45;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'en',
        'lib/MediaWords/Languages/resources/en_nonbreaking_prefixes.txt', $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
