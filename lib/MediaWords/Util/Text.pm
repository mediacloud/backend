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

    ##
    ## WARNING the Text::Similarity::Overlaps object MUST be assigned to a temporary variable
    ## calling getSimilarityStrings directly on the result of Text::Similarity::Overlaps->new( ) results in a memory leak.
    ##  This leak only occurs under certain so it won't show up in toy test programs. However, it consistently occured
    ## in the MediaWords::DBI::Downloads::extractor_results_for_download() call chain until this fix.
    ##
    my $sim = Text::Similarity::Overlaps->new( { normalize => 1, verbose => 0 } );
    my $score = $sim->getSimilarityStrings( $text_1, $text_2 );

    return $score;
}

1;

