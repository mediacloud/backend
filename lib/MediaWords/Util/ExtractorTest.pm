package MediaWords::Util::ExtractorTest;
use MediaWords::CommonLibs;

use strict;

use Data::Dumper;

use HTML::TagCloud;
use List::MoreUtils;

sub get_lines_that_should_be_in_story
{
    ( my $download, my $dbs ) = @_;

    my @story_lines = $dbs->query(
        "select * from extractor_training_lines where extractor_training_lines.downloads_id = ? order by line_number ",
        $download->{ downloads_id } )->hashes;

    my $line_should_be_in_story = {};

    for my $story_line ( @story_lines )
    {
        $line_should_be_in_story->{ $story_line->{ line_number } } = $story_line->{ required } ? 'required' : 'optional';
    }

    return $line_should_be_in_story;
}

sub get_cached_extractor_line_scores
{
    ( my $download, my $dbs ) = @_;

    return $dbs->query( " SELECT  * from extractor_results_cache where downloads_id = ? order by line_number asc ",
        $download->{ downloads_id } )->hashes;
}

1;
