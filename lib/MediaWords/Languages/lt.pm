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

sub get_language_code
{
    return 'lt';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/lt_stoplist.txt' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/lt_stoplist.txt' );
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/lt_stoplist.txt' );
}

sub stem
{
    my $self = shift;

    # (Re-)initialize stemmer if needed
    if ( $self->lt_stemmer == 0 )
    {
        $self->lt_stemmer( Lingua::Stem::Snowball::Lt->new() );
    }

    my @stems = $self->lt_stemmer->stem( \@_ );

    return \@stems;
}

sub get_word_length_limit
{
    my $self = shift;

    # The two longest Lithuanian words are 37 letters long: 1) the adjective
    # septyniasdešimtseptyniastraipsniuose – the plural locative case of the
    # adjective septyniasdešimtseptyniastraipsnis, meaning "(object) with
    # seventy-seven articles"; 2) the participle
    # nebeprisikiškiakopūsteliaudavusiuose, "in those that were repeatedly
    # unable to pick enough of small wood-sorrels in the past" – the plural
    # locative case of past iterative active participle of verb
    # kiškiakopūsteliauti meaning "to pick wood-sorrels" (edible forest plant
    # with sour taste, word by word translation "rabbit cabbage"). The word
    # is commonly attributed to famous Lithuanian language teacher Jonas
    # Kvederaitis, who actually used the plural first person of past iterative
    # tense, nebeprisikiškiakopūstaudavome.[citation needed]
    return 37;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'lt',
        'lib/MediaWords/Languages/resources/lt_nonbreaking_prefixes.txt', $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
