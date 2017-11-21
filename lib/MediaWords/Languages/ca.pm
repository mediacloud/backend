package MediaWords::Languages::ca;
use Moose;
with 'MediaWords::Languages::Language';

#
# Catalan
#

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub get_language_code
{
    return 'ca';
}

sub fetch_and_return_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/ca_stopwords.txt' );
}

sub stem
{
    my $self = shift;

    # Until the Catalan stemmer gets ported to Perl / Python, Spanish will have to do:
    #
    # http://snowball.tartarus.org/algorithms/catalan/stemmer.html
    return $self->_stem_with_lingua_stem_snowball( 'es', 'UTF-8', \@_ );
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return $self->_tokenize_text_with_lingua_sentence( 'ca',
        'lib/MediaWords/Languages/resources/ca_nonbreaking_prefixes.txt', $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
