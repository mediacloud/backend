package MediaWords::Util::HeuristicExtractor;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;

use Data::Dumper;

use Moose;

with 'MediaWords::Util::Extractor';

sub getScoresAndLines
{
    my ( $self, $line_info, $preprocessed_lines ) = @_;

    my $scores = MediaWords::Crawler::HeuristicLineScoring::_score_lines_with_line_info( $line_info );
    my @extracted_lines = map { $_->{ line_number } } grep { $_->{ is_story } } @{ $scores };

    my $extracted_lines = \@extracted_lines;

    return {
        included_line_numbers => $extracted_lines,
        scores                => $scores,
    };
}

sub getExtractedLines
{
    my ( $self, $line_info ) = @_;

    my $scores_and_lines = $self->getScoresAndLines( $line_info );

    return $scores_and_lines->{ included_line_numbers };
}

sub extractor_version
{
    return 'heuristic-1.0';
}

1;
