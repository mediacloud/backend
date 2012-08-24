package MediaWords::Languages::en_US_and_ru_RU;
use Moose;
with 'MediaWords::Languages::Language';

#
# This is a language plug-in for both the English and Russian languages.
#

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;
use Lingua::EN::Sentence::MediaWords;

use MediaWords::Languages::en_US;
use MediaWords::Languages::ru_RU;

# Language plug-ins
my $lang_en = MediaWords::Languages::en_US->new();
my $lang_ru = MediaWords::Languages::ru_RU->new();

# Stemmers
my $stemmer_en = Lingua::Stem::Snowball->new( lang => 'en', encoding => 'UTF-8' );
my $stemmer_ru = Lingua::Stem::Snowball->new( lang => 'ru', encoding => 'UTF-8' );

sub get_language_code
{
    return 'en_US_and_ru_RU';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;

    # Join English and Russian stopwords together
    my %stopwords = ( %{ $lang_en->fetch_and_return_tiny_stop_words() }, %{ $lang_ru->fetch_and_return_tiny_stop_words() } );
    return \%stopwords;
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;

    # Join English and Russian stopwords together
    my %stopwords =
      ( %{ $lang_en->fetch_and_return_short_stop_words() }, %{ $lang_ru->fetch_and_return_short_stop_words() } );
    return \%stopwords;
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;

    # Join English and Russian stopwords together
    my %stopwords = ( %{ $lang_en->fetch_and_return_long_stop_words() }, %{ $lang_ru->fetch_and_return_long_stop_words() } );
    return \%stopwords;
}

sub stem
{
    my $self = shift;

    # Run through both stemmers. The idea is that the English stemmer shouldn't attempt to stem Cyrillic characters,
    # and the Russian stemmer should ignore Latin characters.
    # We don't use the helper of Language.pm because it tries to keep just one instance of Lingua::Stem::Snowball,
    # and we need two (one for English and one for Russian).
    my @stems = $stemmer_en->stem( \@_ );
    @stems = $stemmer_ru->stem( \@stems );
    return \@stems;
}

sub get_word_length_limit
{
    my $self = shift;
    return 256;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;
    return Lingua::EN::Sentence::MediaWords::get_sentences( $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
