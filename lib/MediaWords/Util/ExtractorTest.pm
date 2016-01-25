package MediaWords::Util::ExtractorTest;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;

use Data::Dumper;

use HTML::TagCloud;
use List::MoreUtils;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use HTML::Strip;
use MediaWords::Util::HTML;
use MediaWords::Crawler::AnalyzeLines;
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use MediaWords::Languages::en;

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

    $ret = MediaWords::Crawler::AnalyzeLines::get_info_for_lines( $preprocessed_lines, $story_title, $story_description );

    return $ret;
}

my $_processed_lines_cache = {};

sub get_preprocessed_content_lines_for_download($$)
{
    my ( $db, $download ) = @_;

    if ( defined( $_processed_lines_cache->{ $download->{ downloads_id } } ) )
    {
        return $_processed_lines_cache->{ $download->{ downloads_id } };
    }

    my $preprocessed_lines = MediaWords::DBI::Downloads::fetch_preprocessed_content_lines( $db, $download );

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
sub get_character_count_for_story($$$)
{
    my ( $db, $download, $line_should_be_in_story ) = @_;
    my $lines = MediaWords::Util::ExtractorTest::get_preprocessed_content_lines_for_download( $db, $download );
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
    my $lang                   = MediaWords::Languages::en->new();

    my $all_sentences = [];
    for my $line_number ( @{ $line_numbers } )
    {
        my $line_text = $preprocessed_lines->[ $line_number ];

        say "Line text: $line_text";

        $line_text = html_strip( $line_text );

        say "Line text no html: $line_text";

        my $sentences = $lang->get_sentences( $line_text );
        unless ( defined $sentences )
        {
            die "Sentences for text '$line_text' is undefined.";
        }

        push( @{ $all_sentences }, map { html_strip( $_ ) } @{ $sentences } );
    }

    my $dup_story_sentences = MediaWords::StoryVectors::get_dup_story_senteces( $dbs, $story, $all_sentences );

    my $dup_sentences_lookup = {};
    map { $dup_sentences_lookup->{ $_->{ sentence } } = 1 } @{ $dup_story_sentences };

    for my $sentence ( @{ $all_sentences } )
    {
        $all_sentences++;

        my $dss = $dup_sentences_lookup->{ $sentence };
        if ( !$dss )
        {
            $sentences_missing++;
        }
        elsif ( $dss->{ is_dup } )
        {
            $sentences_dedupped++;
        }
        else
        {
            $sentences_not_dedupped++;
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

sub compare_extraction_with_training_data
{
    my ( $line_should_be_in_story, $extracted_lines, $download, $preprocessed_lines, $dbs, $line_info, $_test_sentences ) =
      @_;

    #say STDERR Dumper( $line_info );

    my @extracted_lines = @{ $extracted_lines };

    my @missing_lines = _get_missing_lines( $line_should_be_in_story, $extracted_lines );

    my @extra_lines = _get_extra_lines( $line_should_be_in_story, $extracted_lines );

    my @correctly_included_lines = _get_correctly_included_lines( $line_should_be_in_story, $extracted_lines );

    my $missing_lines            = \@missing_lines;
    my $extra_lines              = \@extra_lines;
    my $correctly_included_lines = \@correctly_included_lines;

    my $non_optional_non_autoexcluded_line_count =
      _get_non_optional_non_autoexcluded_line_count( $line_should_be_in_story, $line_info );

    my $line_level_results = get_line_level_extractor_results( $line_should_be_in_story, $extra_lines, $missing_lines,
        $non_optional_non_autoexcluded_line_count );

    my $character_level_results =
      get_character_level_extractor_results( $download, $line_should_be_in_story, $missing_lines, $extra_lines,
        $correctly_included_lines, $preprocessed_lines, $line_info );

    my $sentence_level_results = {};

    if ( $_test_sentences )
    {
        $sentence_level_results =
          get_story_level_extractor_results( $download, $line_should_be_in_story, $missing_lines, $extra_lines,
            \@correctly_included_lines, $preprocessed_lines, $dbs );
    }

    my $ret = { %{ $line_level_results }, %{ $character_level_results }, %{ $sentence_level_results }, };

    return $ret;
}

sub _get_required_lines
{
    my ( $line_should_be_in_story ) = @_;

    my @required_lines = grep { $line_should_be_in_story->{ $_ } eq 'required' } keys %{ $line_should_be_in_story };

    return @required_lines;
}

sub _get_optional_lines
{
    my ( $line_should_be_in_story ) = @_;

    my @optional_lines = grep { $line_should_be_in_story->{ $_ } eq 'optional' } keys %{ $line_should_be_in_story };

    return @optional_lines;
}

sub _get_missing_lines
{
    my ( $line_should_be_in_story, $extracted_lines ) = @_;

    my @extracted_lines = @{ $extracted_lines };

    my @required_lines = _get_required_lines( $line_should_be_in_story );
    my @optional_lines = _get_optional_lines( $line_should_be_in_story );

    my @missing_lines = get_unique( [ \@required_lines, \@extracted_lines ] );

    return @missing_lines;
}

sub _get_extra_lines
{
    my ( $line_should_be_in_story, $extracted_lines ) = @_;

    my @extracted_lines = @{ $extracted_lines };

    my @required_lines = _get_required_lines( $line_should_be_in_story );
    my @optional_lines = _get_optional_lines( $line_should_be_in_story );

    my @extra_lines = get_unique( [ \@extracted_lines, get_union_ref( [ \@required_lines, \@optional_lines ] ) ] );

    return @extra_lines;
}

sub _get_non_optional_non_autoexcluded_line_count
{

    my ( $line_should_be_in_story, $line_info ) = @_;

    my @optional_lines = _get_optional_lines( $line_should_be_in_story );

    my $non_autoexcluded = [ grep { !$_->{ auto_excluded } } @{ $line_info } ];

    my $non_autoexcluded_line_numbers = [ map { $_->{ line_number } } @$non_autoexcluded ];

    # say Dumper ( \@optional_lines );
    # say Dumper ( $non_autoexcluded );
    # say Dumper ( $non_autoexcluded_line_numbers );
    # say Dumper ( scalar ( @ $non_autoexcluded_line_numbers ) );

    return scalar( @$non_autoexcluded_line_numbers );
}

sub _get_correctly_included_lines
{
    my ( $line_should_be_in_story, $extracted_lines ) = @_;

    my @extracted_lines = @{ $extracted_lines };

    my @required_lines = _get_required_lines( $line_should_be_in_story );
    my @optional_lines = _get_optional_lines( $line_should_be_in_story );

    my @extra_lines = get_unique( [ \@extracted_lines, get_union_ref( [ \@required_lines, \@optional_lines ] ) ] );

    return @extra_lines;
}

sub get_line_level_extractor_results
{
    my ( $line_should_be_in_story, $extra_lines, $missing_lines, $non_optional_non_autoexclude_line_count ) = @_;

    my $story_line_count = scalar( keys %{ $line_should_be_in_story } );

    my $extra_line_count   = scalar( @{ $extra_lines } );
    my $missing_line_count = scalar( @{ $missing_lines } );

    my $ret = {
        story_line_count                        => $story_line_count,
        extra_line_count                        => $extra_line_count,
        missing_line_count                      => $missing_line_count,
        non_optional_non_autoexclude_line_count => $non_optional_non_autoexclude_line_count,
    };

    return $ret;
}

sub get_character_level_extractor_results
{
    my ( $download, $line_should_be_in_story, $missing_lines, $extra_lines, $correctly_included_lines, $preprocessed_lines,
        $line_info )
      = @_;

    my $extra_line_count   = scalar( @{ $extra_lines } );
    my $missing_line_count = scalar( @{ $missing_lines } );

    my $errors = 0;

    die unless $line_info;

    #say STDERR Dumper ( $line_info );

    #say STDERR "Dumping";

    #say STDERR "correctly_included_lines " . Dumper( $correctly_included_lines );

    #say STDERR Dumper ( [ map { $line_info->[ $_ ]->{html_stripped_text_length } } @$correctly_included_lines ] );
    my $correctly_included_character_length =
      sum( map { $line_info->[ $_ ]->{ html_stripped_text_length } } @$correctly_included_lines );

    my $story_lines_character_length =
      sum( map { $line_info->[ $_ ]->{ html_stripped_text_length } // 0 } keys %{ $line_should_be_in_story } );
    my $missing_lines_character_length =
      sum( map { $line_info->[ $_ ]->{ html_stripped_text_length } // 0 } @$missing_lines );
    my $extra_lines_character_length = sum( map { $line_info->[ $_ ]->{ html_stripped_text_length } // 0 } @$extra_lines );

    $correctly_included_character_length ||= 0;

    $missing_lines_character_length ||= 0;
    $extra_lines_character_length   ||= 0;

    my $ret = {
        story_characters   => $story_lines_character_length,
        extra_characters   => $extra_lines_character_length,
        errors             => $errors,
        missing_characters => $missing_lines_character_length,
        accuracy           => (
            $story_lines_character_length
            ? int(
                ( $extra_lines_character_length + $missing_lines_character_length ) / $story_lines_character_length * 100
              )
            : 0
        ),
    };

    return $ret;
}

1;
