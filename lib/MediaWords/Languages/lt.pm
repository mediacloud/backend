package MediaWords::Languages::lt;
use Moose;
with 'MediaWords::Languages::Language';

#
# Lithuanian
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Lingua::Stem::Snowball::Lt;

# Lingua::Stem::Snowball::Lt instance (if needed), lazy-initialized in stem()
has 'lt_stemmer' => ( is => 'rw', default => 0 );

sub language_code
{
    return 'lt';
}

sub stop_words_map
{
    my $self = shift;
    return $self->_stop_words_map_from_file( 'lib/MediaWords/Languages/resources/lt_stopwords.txt' );
}

sub stem
{
    my ( $self, $words ) = @_;

    # (Re-)initialize stemmer if needed
    if ( $self->lt_stemmer == 0 )
    {
        $self->lt_stemmer( Lingua::Stem::Snowball::Lt->new() );
    }

    my $stems = [ $self->lt_stemmer->stem( $words ) ];

    return $stems;
}

sub split_text_to_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'lt',
        'lib/MediaWords/Languages/resources/lt_nonbreaking_prefixes.txt', $story_text );
}

sub split_sentence_to_words
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
