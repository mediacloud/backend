package MediaWords::Languages::de;
use Moose;
with 'MediaWords::Languages::Language';

#
# German
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub language_code
{
    return 'de';
}

sub stop_words_map
{
    my $self = shift;
    return $self->_stop_words_map_from_file( 'lib/MediaWords/Languages/resources/de_stopwords.txt' );
}

sub stem
{
    my ( $self, $words ) = @_;
    return $self->_stem_with_lingua_stem_snowball( 'de', 'UTF-8', $words );
}

sub split_text_to_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'de',
        'lib/MediaWords/Languages/resources/de_nonbreaking_prefixes.txt', $story_text );
}

sub split_sentence_to_words
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
