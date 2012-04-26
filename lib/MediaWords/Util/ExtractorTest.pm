package MediaWords::Util::ExtractorTest;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;

use Data::Dumper;

use HTML::TagCloud;
use List::MoreUtils;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use HTML::Strip;
use MediaWords::Util::HTML;
use MediaWords::Crawler::AnalyzeLines;

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

sub get_extractor_scores_for_lines
{
    ( my $lines, my $story_title, my $story_description, my $download, my $dbs, my $use_cache ) = @_;

    my $ret;

    if ( $use_cache )
    {
        $ret = MediaWords::Util::ExtractorTest::get_cached_extractor_line_scores( $download, $dbs );
    }

    if ( !defined( $ret ) || !@{ $ret } )
    {
        $ret = MediaWords::Crawler::Extractor::score_lines( $lines, $story_title, $story_description, );
        store_extractor_line_scores( $ret, $lines, $download, $dbs );
    }
    return $ret;
}

sub get_line_analysis_info
{
    my ( $download, $dbs, $preprocessed_lines ) = @_;

    my $ret;

    my $story_title =
      $dbs->query( "SELECT title FROM stories where stories.stories_id=? ", $download->{ stories_id } )->flat->[ 0 ];
    my $story_description =
      $dbs->query( "SELECT description FROM stories where stories.stories_id=? ", $download->{ stories_id } )->flat->[ 0 ];

    $ret = MediaWords::Crawler::AnalyzeLines::get_info_for_lines( $preprocessed_lines, $story_title, $story_description, );

    return $ret;
}

my $_processed_lines_cache = {};

sub get_preprocessed_content_lines_for_download
{
    ( my $download ) = @_;

    if ( defined( $_processed_lines_cache->{ $download->{ downloads_id } } ) )
    {
        return $_processed_lines_cache->{ $download->{ downloads_id } };
    }

    my $preprocessed_lines = MediaWords::DBI::Downloads::fetch_preprocessed_content_lines( $download );

    $_processed_lines_cache = { $download->{ downloads_id } => $preprocessed_lines };

    return $preprocessed_lines;
}

sub store_extractor_line_scores
{
    ( my $scores, my $lines, my $download, my $dbs ) = @_;

    $dbs->begin_work;

    $dbs->query( 'DELETE FROM extractor_results_cache where downloads_id = ?', $download->{ downloads_id } );

    my $line_number = 0;
    for my $score ( @{ $scores } )
    {

        #print (keys %{$score}) . "\n";
        $dbs->insert(
            'extractor_results_cache',
            {
                is_story                => $score->{ is_story },
                explanation             => $score->{ explanation },
                discounted_html_density => $score->{ discounted_html_density },
                html_density            => $score->{ html_density },
                downloads_id            => $download->{ downloads_id },
                line_number             => $line_number,
            }
        );

        $line_number++;
    }

    $dbs->commit;
}

#returns the sum of the string length for each line the training table says should be in the story.
sub get_character_count_for_story
{
    ( my $download, my $line_should_be_in_story ) = @_;
    my $lines = MediaWords::Util::ExtractorTest::get_preprocessed_content_lines_for_download( $download );
    my $story_characters = sum( map { html_stripped_text_length( $lines->[ $_ ] ) } keys %{ $line_should_be_in_story } );

    return $story_characters;
}

sub get_sentence_info_for_lines
{
    my ( $line_numbers, $preprocessed_lines, $story, $dbs ) = @_;

    my $sentences_total        = 0;
    my $sentences_dedupped     = 0;
    my $sentences_not_dedupped = 0;
    my $sentences_missing      = 0;

    for my $line_number ( @{ $line_numbers } )
    {
        my $line_text = $preprocessed_lines->[ $line_number ];

        say "Line text: $line_text";

        $line_text = html_strip( $line_text );

        say "Line text no html: $line_text";

        my $sentences = Lingua::EN::Sentence::MediaWords::get_sentences( $line_text );

        foreach my $sentence ( @{ $sentences } )
        {

            $sentence = html_strip( $sentence );

            #say "Sentence: '$sentence'";

            my $dup_sentence = $dbs->query(
                "select * from story_sentence_counts " .
                  "  where sentence_md5 = md5( ? ) and media_id = ? and publish_week = date_trunc( 'week', ?::date )" .
                  "  order by story_sentence_counts_id limit 1",
                $sentence,
                $story->{ media_id },
                $story->{ publish_date }
            )->hash;

            $sentences_total++;

            if ( $dup_sentence )
            {
                if ( $dup_sentence->{ sentence_count } <= 1 )
                {
                    $sentences_not_dedupped++;
                }
                else
                {
                    $sentences_dedupped++;
                }
            }
            else
            {
                $sentences_missing++;
            }
        }

    }

    my $ret = {
        sentences_total      => $sentences_total,
        sentences_not_dupped => $sentences_not_dedupped,
        sentences_dupped     => $sentences_dedupped,
        sentences_missing    => $sentences_missing,
    };

}

sub html_stripped_text_length
{
    my $html_text = shift;

    if ( !$html_text )
    {
        return 0;
    }

    my $hs = HTML::Strip->new();

    my $tmp = ( $hs->parse( $html_text ) );
    $hs->eof();

    my $ret = length( $tmp );

    return $ret;
}

sub get_extracted_lines_for_story
{
    ( my $download, my $dbs, my $preprocessed_lines, my $use_cache ) = @_;

    my $scores = [];

    {
        my $story_title =
          $dbs->query( "SELECT title FROM stories where stories.stories_id=? ", $download->{ stories_id } )->flat->[ 0 ];
        my $story_description =
          $dbs->query( "SELECT description FROM stories where stories.stories_id=? ", $download->{ stories_id } )
          ->flat->[ 0 ];

        $scores = MediaWords::Util::ExtractorTest::get_extractor_scores_for_lines( $preprocessed_lines, $story_title,
            $story_description, $download, $dbs, $use_cache );
    }

    my @extracted_lines = map { $_->{ line_number } } grep { $_->{ is_story } } @{ $scores };

    return @extracted_lines;
}

1;
