package MediaWords::Util::Text;

# various functions for manipulating text

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Languages::Language;
use List::Util qw(min);
use Memoize;
use Tie::Cache;
use Encode;
use utf8;

# Cache output of _words_in_text() because get_similarity_score() is called
# many times with the very same first parameter (which is "title+description")
my %_words_in_text_cache;
tie %_words_in_text_cache, 'Tie::Cache', {
    MaxCount => 1024,          # 1024 entries
    MaxBytes => 1024 * 1024    # 1 MB of space
};

memoize '_words_in_text', SCALAR_CACHE => [ HASH => \%_words_in_text_cache ];

# Get words and their frequencies from text
# Parameters:
# * Text string
# * Language code
# Returns:
# * text word count
# * hash to words and their frequencies in the text (not hashref because
#   memoize doesn't know how to cache memory addresses)
# die()s on error
sub _words_in_text($$)
{
    my ( $text, $language_code ) = @_;

    # Languages are preinitialized and thus cached (one hash lookup is being used here)
    my $lang = MediaWords::Languages::Language::language_for_code( $language_code );
    unless ( $lang )
    {
        die "Language for language code \"$language_code\" is null.\n";
    }

    # Stopword stems are cached the first time they're accessed
    my $stopword_stems_hashref = $lang->get_tiny_stop_word_stems();

    # Tokenize into separate words
    # (lowercasing will be done after tokenizing and stemming because tokenizer
    # might use case hints to do its job)
    $text = $lang->tokenize( $text );

    # Stem words
    $text = $lang->stem( @{ $text } );

    my %words_in_text   = ();
    my $text_word_count = 0;
    foreach my $word ( @{ $text } )
    {

        # $lang->tokenize() usually lowercases the word, but we can't be sure
        # about that so we do it again here
        $word = lc( $word );

        # Skip stopwords (assume that stopwords are lowercase already)
        if ( exists $stopword_stems_hashref->{ $word } )
        {
            next;
        }

        ++$text_word_count;

        ++$words_in_text{ $word };
    }

    return ( $text_word_count, %words_in_text );
}

# Get similarity score between two UTF-8 strings
# Parameters:
# * First UTF-8 encoded string
# * Second UTF-8 encoded string
# * (optional) Language code, e.g. "en"
sub get_similarity_score($$;$)
{
    my ( $text_1, $text_2, $language_code ) = @_;

    unless ( defined( $text_1 ) and defined( $text_2 ) )
    {
        die "Both first and second text must be defined.\n";
    }

    my $text_1_length = length( $text_1 );
    my $text_2_length = length( $text_2 );
    unless ( $text_1_length > 0 and $text_2_length > 0 )
    {
        if ( $text_1_length == 0 and $text_2_length == 0 )
        {
            # Empty texts are assumed to be 100% same
            return 1;
        }
        else
        {
            # If one of the texts is empty, they're 0% same
            return 0;
        }
    }

    unless ( $language_code )
    {
        $language_code = MediaWords::Languages::Language::default_language_code();
        warn "Language code is undefined, using the default language \"$language_code\".\n";
    }

    # Split both texts into words, count frequencies
    my ( $text_1_word_count, %words_in_text_1 ) = _words_in_text( $text_1, $language_code );
    my ( $text_2_word_count, %words_in_text_2 ) = _words_in_text( $text_2, $language_code );

    my %words_from_text_2_present_in_text_1       = ();
    my $words_from_text_2_present_in_text_1_count = 0;

    # We 'foreach' words_in_text_2, not words_in_text_1, because title+description
    # (passed as parameter #1) is usually longer than a text line (passed as
    # parameter #2)
    foreach my $word ( keys %words_in_text_2 )
    {

        if ( exists $words_in_text_1{ $word } )
        {
            my $overlapping_word_count = min( $words_in_text_2{ $word }, $words_in_text_1{ $word } );

            $words_from_text_2_present_in_text_1{ $word } = $overlapping_word_count;
            $words_from_text_2_present_in_text_1_count += $overlapping_word_count;
        }
    }

    my $raw_score = $words_from_text_2_present_in_text_1_count;

    if ( $raw_score == 0 )
    {
        # No word overlap
        return 0;
    }

    # say "Raw score: $raw_score";
    # say "Text 1 word count: $text_1_word_count";
    # say "Text 2 word count: $text_2_word_count";

    my $precision = $raw_score / $text_2_word_count;
    my $recall    = $raw_score / $text_1_word_count;
    my $f_measure = 2 * $precision * $recall / ( $precision + $recall );

    # say "Precision: $precision";
    # say "Recall: $recall";

    return $f_measure;
}

# Check whether the string is valid UTF-8
sub is_valid_utf8($)
{
    my $s = shift;

    my $valid = 1;

    Encode::_utf8_on( $s );

    $valid = 0 unless ( utf8::valid( $s ) );

    Encode::_utf8_off( $s );

    return $valid;
}

1;

