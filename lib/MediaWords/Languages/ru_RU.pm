package MediaWords::Languages::ru_RU;
use Moose;
with 'MediaWords::Languages::Language';

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;
use Lingua::EN::Sentence::MediaWords;

sub get_language_code
{
    return 'ru_RU';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/ru_RU_stoplist_tiny.txt' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/ru_RU_stoplist_short.txt' );
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
    return 256;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;

    # FIXME
    return Lingua::EN::Sentence::MediaWords::get_sentences( $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
