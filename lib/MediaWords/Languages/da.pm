package MediaWords::Languages::da;
use Moose;
with 'MediaWords::Languages::Language';

#
# Danish
#

use strict;
use warnings;

use Modern::Perl "2012";
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
    return 256;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'da', 'lib/MediaWords/Languages/da_nonbreaking_prefixes.txt',
        $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
