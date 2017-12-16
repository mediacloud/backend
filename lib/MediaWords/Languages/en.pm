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

sub language_code
{
    return 'en';
}

sub stop_words_map
{
    my $self = shift;
    return $self->_stop_words_map_from_file( 'lib/MediaWords/Languages/resources/en_stopwords.txt' );
}

sub stem
{
    my ( $self, $words ) = @_;

    # Normalize apostrophe so that "it’s" and "it's" get treated identically
    # (it's being done in _tokenize_with_spaces() too but let's not assume that
    # all tokens that are to be stemmed go through sentence tokenization first)
    s/’/'/g for @{ $words };

    return $self->_stem_with_lingua_stem_snowball( 'en', 'UTF-8', $words );
}

sub split_text_to_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'en',
        'lib/MediaWords/Languages/resources/en_nonbreaking_prefixes.txt', $story_text );
}

sub split_sentence_to_words
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
