package MediaWords::Languages::pt;
use Moose;
with 'MediaWords::Languages::Language';

#
# Portuguese
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'pt';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'pt', 'UTF-8' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'pt', 'UTF-8' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_with_lingua_stopwords( 'pt', 'UTF-8' );
}

sub stem
{
    my $self = shift;
    return $self->_stem_with_lingua_stem_snowball( 'pt', 'UTF-8', \@_ );
}

sub get_word_length_limit
{
    my $self = shift;

    # The 46-letter word pneumoultramicroscopicossilicovulcanoconioticozinhos
    # (plural diminutive of pneumoultramicroscopicossilicovulcanoconiótico) is
    # the longest word[citation needed]. It is an adjective referring to a
    # sufferer of the disease pneumonoultramicroscopicsilicovolcanoconiosis.
    # The 29-letter word anticonstitucionalissimamente (adverb, meaning "in a
    # very unconstitutional way") is recognized as being the longest
    # non-technical word.[citation needed]
    # (http://en.wikipedia.org/wiki/Longest_words#Portuguese)
    return 46;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'pt',
        'lib/MediaWords/Languages/resources/pt_nonbreaking_prefixes.txt', $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
