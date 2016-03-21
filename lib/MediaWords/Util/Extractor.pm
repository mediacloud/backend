package MediaWords::Util::Extractor;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;

use Data::Dumper;

use Moose::Role;

requires 'getExtractedLines';
requires 'getScoresAndLines';
requires 'extractor_version';

sub getExtractedLines
{
    my ( $self, $line_infos, $preprocessed_lines ) = @_;

    my $scores_and_lines = $self->getScoresAndLines( $line_infos, $preprocessed_lines );

    return $scores_and_lines->{ included_line_numbers };
}

sub extract_preprocessed_lines_for_story
{
    my ( $self, $lines, $story_title, $story_description ) = @_;

    if ( !defined( $lines ) )
    {
        return;
    }

    my $line_info = MediaWords::Crawler::AnalyzeLines::get_info_for_lines( $lines, $story_title, $story_description );

    my $scores_and_lines = $self->getScoresAndLines( $line_info, $lines );

    return {

        included_line_numbers => $scores_and_lines->{ included_line_numbers },
        download_lines        => $lines,
        scores                => $scores_and_lines->{ scores },
    };
}

1;
