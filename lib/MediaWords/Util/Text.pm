package MediaWords::Util::Text;

# various functions for manipulating text

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Languages::Language;
use Text::Similarity::Overlaps;
use Data::Dumper;

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

    my $lang = MediaWords::Languages::Language::language_for_code( $language_code );
    unless ( $lang )
    {
        die "Language for language code \"$language_code\" is null.\n";
    }

    my $stopword_stems_hashref = $lang->get_tiny_stop_word_stems();

    # Tokenize into separate words
    # (lowercasing will be done after tokenizing and stemming because tokenizer
    # uses case hints to do its job)
    $text_1 = $lang->tokenize( $text_1 );
    $text_2 = $lang->tokenize( $text_2 );

    # Stem words
    $text_1 = $lang->stem( @{ $text_1 } );
    $text_2 = $lang->stem( @{ $text_2 } );

    my %words_in_text_1   = ();
    my $text_1_word_count = 0;
    foreach my $word ( @{ $text_1 } )
    {

        # $lang->tokenize() usually lowercases the word, but we can't be sure
        # about that so we do it again here
        $word = lc( $word );

        # Skip stopwords (assume that stopwords are lowercase already)
        if ( exists $stopword_stems_hashref->{ $word } )
        {
            next;
        }

        ++$text_1_word_count;

        ++$words_in_text_1{ $word };
    }

    my %words_from_text_2_present_in_text_1       = ();
    my $words_from_text_2_present_in_text_1_count = 0;
    my $text_2_word_count                         = 0;
    foreach my $word ( @{ $text_2 } )
    {

        # $lang->tokenize() usually lowercases the word, but we can't be sure
        # about that so we do it again here
        $word = lc( $word );

        # Skip stopwords (assume that stopwords are lowercase already)
        if ( exists $stopword_stems_hashref->{ $word } )
        {
            next;
        }

        ++$text_2_word_count;

        if ( exists $words_in_text_1{ $word } )
        {
            $words_from_text_2_present_in_text_1{ $word } ||= 0;
            if ( $words_from_text_2_present_in_text_1{ $word } < $words_in_text_1{ $word } )
            {
                ++$words_from_text_2_present_in_text_1{ $word };
                ++$words_from_text_2_present_in_text_1_count;
            }
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

1;

