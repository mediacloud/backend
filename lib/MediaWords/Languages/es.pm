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

sub language_code
{
    return 'es';
}

sub stop_words_map
{
    my $self = shift;
    return $self->_stop_words_map_from_file( 'lib/MediaWords/Languages/resources/es_stopwords.txt' );
}

sub stem
{
    my ( $self, $words ) = @_;
    return $self->_stem_with_lingua_stem_snowball( 'es', 'UTF-8', $words );
}

sub split_text_to_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'es',
        'lib/MediaWords/Languages/resources/es_nonbreaking_prefixes.txt', $story_text );
}

sub split_sentence_to_words
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
