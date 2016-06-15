package MediaWords::Languages::hu;
use Moose;
with 'MediaWords::Languages::Language';

#
# Hungarian
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
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

1;
