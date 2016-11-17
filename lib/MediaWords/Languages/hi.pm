package MediaWords::Languages::hi;

#
# Hindi
#

use strict;
use warnings;
use utf8;

use Moose;
with 'MediaWords::Languages::Language';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

sub get_language_code
{
    return 'hi';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->fetch_and_return_long_stop_words();
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->fetch_and_return_long_stop_words();
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/hi_stoplist.txt' );
}

sub stem
{
    my $self = shift;

# Ported from Python code which, in turn, is a port of Lucene's HindiStemmer.java:
# * http://research.variancia.com/hindi_stemmer/
# * https://github.com/apache/lucene-solr/blob/master/lucene/analysis/common/src/java/org/apache/lucene/analysis/hi/HindiStemmer.java
# * http://computing.open.ac.uk/Sites/EACLSouthAsia/Papers/p6-Ramanathan.pdf
    sub _stem_hindi_word($)
    {
        my $word = shift;

        my $suffixes = {
            1 => [ "ो", "े", "ू", "ु", "ी", "ि", "ा" ],
            2 => [
                "कर", "ाओ", "िए", "ाई", "ाए", "ने", "नी", "ना",
                "ते", "ीं", "ती", "ता", "ाँ", "ां", "ों", "ें"
            ],
            3 => [
                "ाकर", "ाइए", "ाईं", "ाया", "ेगी", "ेगा", "ोगी", "ोगे",
                "ाने", "ाना", "ाते", "ाती", "ाता", "तीं", "ाओं", "ाएं",
                "ुओं", "ुएं", "ुआं"
            ],
            4 => [
                "ाएगी", "ाएगा", "ाओगी", "ाओगे", "एंगी", "ेंगी",
                "एंगे", "ेंगे", "ूंगी", "ूंगा", "ातीं", "नाओं",
                "नाएं", "ताओं", "ताएं", "ियाँ", "ियों", "ियां"
            ],
            5 => [
                "ाएंगी", "ाएंगे", "ाऊंगी", "ाऊंगा",
                "ाइयाँ", "ाइयों", "ाइयां"
            ],
        };

        for ( my $level = 5 ; $level >= 1 ; --$level )
        {
            if ( length( $word ) > $level + 1 )
            {
                for my $suffix ( @{ $suffixes->{ $level } } )
                {
                    if ( $word =~ qr/\Q$suffix\E$/ )    # ends with
                    {
                        return substr( $word, 0, $level * -1 );
                    }
                }
            }
        }

        return $word;
    }

    my @stems;
    for my $token ( @_ )
    {
        my $stem = _stem_hindi_word( $token );
        unless ( defined $stem )
        {
            LOGDIE "Undefined stem for Hindi token $token";
        }
        push( @stems, $stem );
    }

    return \@stems;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;

    # Replace Hindi's "।" with line break to make Lingua::Sentence split on both "।" and period
    $story_text =~ s/।/।\n\n/gs;

    # No non-breaking prefixes in Hindi, so using English file
    Readonly my $nonbreaking_prefix_file => 'lib/MediaWords/Languages/resources/en_nonbreaking_prefixes.txt';
    return $self->_tokenize_text_with_lingua_sentence( 'en', $nonbreaking_prefix_file, $story_text );
}

sub tokenize
{
    my ( $self, $sentence ) = @_;
    return $self->_tokenize_with_spaces( $sentence );
}

1;
