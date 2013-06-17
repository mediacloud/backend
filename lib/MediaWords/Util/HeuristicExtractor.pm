package MediaWords::Util::HeuristicExtractor;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;

use Data::Dumper;

use Moose;

with 'MediaWords::Util::Extractor';

sub getExtractedLines
{
    my ( $self, $line_info ) = @_;

    my $scores = MediaWords::Crawler::HeuristicLineScoring::_score_lines_with_line_info( $line_info );
    my @extracted_lines = map { $_->{ line_number } } grep { $_->{ is_story } } @{ $scores };

    my $extracted_lines = \@extracted_lines;

    return $extracted_lines;
}

1;
