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

use Lingua::Stem::Snowball::Ca;

# Lingua::Stem::Snowball::Ca instance (if needed), lazy-initialized in stem()
has 'ca_stemmer' => ( is => 'rw', default => 0 );

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

    # (Re-)initialize stemmer if needed
    if ( $self->ca_stemmer == 0 )
    {
        $self->ca_stemmer( Lingua::Stem::Snowball::Ca->new() );
    }

    my @stems = $self->ca_stemmer->stem( \@_ );

    return \@stems;
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
