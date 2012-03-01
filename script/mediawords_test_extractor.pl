#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use Lingua::EN::Sentence::MediaWords;
use Perl6::Say;
use Data::Dumper;
use MediaWords::Util::HTML;
use MediaWords::Util::ExtractorTest;
use Data::Compare;

my $_re_generate_cache = 0;

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

    my ( $line_should_be_in_story, $extra_lines, $missing_lines ) = @_;

    my $story_line_count = scalar( keys %{ $line_should_be_in_story } );

    my $extra_line_count   = scalar( @{ $extra_lines } );
    my $missing_line_count = scalar( @{ $missing_lines } );

    my $ret = {
        story_line_count   => $story_line_count,
        extra_line_count   => $extra_line_count,
        missing_line_count => $missing_line_count,
    };

    return $ret;
}

sub get_character_level_extractor_results
{
    my ( $download, $line_should_be_in_story, $missing_lines,  $extra_lines, $preprocessed_lines, $dbs ) = @_;


    my $extra_line_count   = scalar( @{ $extra_lines } );
    my $missing_line_count = scalar( @{ $missing_lines } );

    my $errors = 0;

    my $story_characters =
      MediaWords::Util::ExtractorTest::get_character_count_for_story( $download, $line_should_be_in_story );

    my $download_errors;

    my $missing_characters = 0;

    for my $missing_line_number ( @$missing_lines )
    {
        $missing_characters +=
          MediaWords::Util::ExtractorTest::html_stripped_text_length( $preprocessed_lines->[ $missing_line_number ] );

        $download_errors .= "missing line $missing_line_number: " . $preprocessed_lines->[ $missing_line_number ] . "\n";
    }
    my $extra_characters = 0;

    for my $extra_line_number ( @$extra_lines )
    {
        $extra_characters +=
          MediaWords::Util::ExtractorTest::html_stripped_text_length( $preprocessed_lines->[ $extra_line_number ] );
        $download_errors .= "extra line $extra_line_number: " . $preprocessed_lines->[ $extra_line_number ] . "\n";
    }

    if ( $download_errors )
    {
        my $story_title =
          $dbs->query( "SELECT title FROM stories where stories.stories_id=? ", $download->{ stories_id } )->flat->[ 0 ];

        print "****\nerrors in download " . $download->{ downloads_id } . ": " . $story_title . "\n" .
          "$download_errors\n****\n";
        $errors++;
    }

    my $ret = {story_characters => $story_characters,
        extra_characters   => $extra_characters,
        errors             => $errors,
        missing_characters => $missing_characters,
	accuracy           => (
            $story_characters
            ? int( ( $extra_characters + $missing_characters ) / $story_characters * 100 )
            : 0
        ),
	      };

    return $ret;
}

sub compare_extraction_with_training_data
{
    my ( $line_should_be_in_story, $extracted_lines, $download, $preprocessed_lines, $dbs ) = @_;

    my @extracted_lines = @{ $extracted_lines };

    my @missing_lines = _get_missing_lines( $line_should_be_in_story, $extracted_lines );

    my @extra_lines = _get_extra_lines( $line_should_be_in_story, $extracted_lines );

    my @correctly_included_lines = _get_correctly_included_lines( $line_should_be_in_story, $extracted_lines );

    my $line_level_results = get_line_level_extractor_results( $line_should_be_in_story, \@extra_lines, \@missing_lines );

    my $character_level_results = get_character_level_extractor_results( $download, $line_should_be_in_story, \@missing_lines,  \@extra_lines, $preprocessed_lines, $dbs ) ;

    my $story = $dbs->find_by_id( 'stories', $download->{ stories_id } );

    #say Dumper( $story );

    my $extra_line_sentence_info =
      MediaWords::Util::ExtractorTest::get_sentence_info_for_lines( [ @extra_lines ], $preprocessed_lines, $story, $dbs );

    my $extra_sentences_dedupped     = $extra_line_sentence_info->{ sentences_dupped };
    my $extra_sentences_not_dedupped = $extra_line_sentence_info->{ sentences_not_dupped };
    my $extra_sentences_missing      = $extra_line_sentence_info->{ sentences_missing };

    my $extra_sentences_total = $extra_line_sentence_info->{ sentences_total };

    my $correctly_included_line_sentence_info =
      MediaWords::Util::ExtractorTest::get_sentence_info_for_lines( [ @correctly_included_lines ],
        $preprocessed_lines, $story, $dbs );

    my $correctly_included_sentences_dedupped     = $correctly_included_line_sentence_info->{ sentences_dupped };
    my $correctly_included_sentences_not_dedupped = $correctly_included_line_sentence_info->{ sentences_not_dupped };
    my $correctly_included_sentences_missing      = $correctly_included_line_sentence_info->{ sentences_missing };

    my $correctly_included_sentences_total = $correctly_included_line_sentence_info->{ sentences_total };

    my $missing_line_sentence_info =
      MediaWords::Util::ExtractorTest::get_sentence_info_for_lines( [ @missing_lines ], $preprocessed_lines, $story, $dbs );

    my $missing_sentences_dedupped     = $missing_line_sentence_info->{ sentences_dupped };
    my $missing_sentences_not_dedupped = $missing_line_sentence_info->{ sentences_not_dupped };
    my $missing_sentences_missing      = $missing_line_sentence_info->{ sentences_missing };

    my $missing_sentences_total = $missing_line_sentence_info->{ sentences_total };

    my $ret = {
        %{ $line_level_results },
        %{ $character_level_results },
        #story_characters => $story_characters,
        #extra_characters   => $extra_characters,
        #errors             => $errors,
        #missing_characters => $missing_characters,
       
        extra_sentences_total        => $extra_sentences_total,
        extra_sentences_dedupped     => $extra_sentences_dedupped,
        extra_sentences_not_dedupped => $extra_sentences_not_dedupped,
        extra_sentences_missing      => $extra_sentences_missing,

        missing_sentences_total        => $missing_sentences_total,
        missing_sentences_dedupped     => $missing_sentences_dedupped,
        missing_sentences_not_dedupped => $missing_sentences_not_dedupped,
        missing_sentences_missing      => $missing_sentences_missing,

        correctly_included_sentences_total        => $correctly_included_sentences_total,
        correctly_included_sentences_dedupped     => $correctly_included_sentences_dedupped,
        correctly_included_sentences_not_dedupped => $correctly_included_sentences_not_dedupped,
        correctly_included_sentences_missing      => $correctly_included_sentences_missing,
    };

    return $ret;
}

sub processDownload
{
    ( my $download, my $dbs ) = @_;

    my $preprocessed_lines = MediaWords::Util::ExtractorTest::get_preprocessed_content_lines_for_download( $download );

    my $line_info       = MediaWords::Util::ExtractorTest::get_line_analysis_info( $download, $dbs, $preprocessed_lines );
    my $scores          = MediaWords::Crawler::HeuristicLineScoring::_score_lines_with_line_info( $line_info );
    my @extracted_lines = map { $_->{ line_number } } grep { $_->{ is_story } } @{ $scores };

    my @extracted_lines_from_get_extracted_lines_for_story =
      MediaWords::Util::ExtractorTest::get_extracted_lines_for_story( $download, $dbs, $preprocessed_lines,
        !$_re_generate_cache );

    if ( !Compare( \@extracted_lines_from_get_extracted_lines_for_story, \@extracted_lines ) )
    {
        say "line_info\n" . Dumper( $line_info );
        say "scores\n" . Dumper( $scores );
        say 'Extracted lines from get_extracted_lines_for_story';
        say Dumper( \@extracted_lines_from_get_extracted_lines_for_story );
        say 'Extracted lines';
        say Dumper( \@extracted_lines );
        die;
    }

    #die unless Compare( \@extracted_lines_from_line_info, \@extracted_lines );

    my $extracted_lines = \@extracted_lines;

    my $line_should_be_in_story = MediaWords::Util::ExtractorTest::get_lines_that_should_be_in_story( $download, $dbs );

    return compare_extraction_with_training_data( $line_should_be_in_story, $extracted_lines, $download, $preprocessed_lines,
        $dbs );
}

sub extractAndScoreDownloads
{

    my $downloads = shift;

    my @downloads = @{ $downloads };

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $download_results = [];

    my $dbs = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    for my $download ( @downloads )
    {
        my $download_result = processDownload( $download, $dbs );

        push( @{ $download_results }, $download_result );
    }

    #say STDERR Dumper( $download_results );

    my $all_story_characters   = sum( map { $_->{ story_characters } } @{ $download_results } );
    my $all_extra_characters   = sum( map { $_->{ extra_characters } } @{ $download_results } );
    my $all_missing_characters = sum( map { $_->{ missing_characters } } @{ $download_results } );
    my $all_story_lines        = sum( map { $_->{ story_line_count } } @{ $download_results } );
    my $all_extra_lines        = sum( map { $_->{ extra_line_count } } @{ $download_results } );
    my $all_missing_lines      = sum( map { $_->{ missing_line_count } } @{ $download_results } );
    my $errors                 = sum( map { $_->{ errors } } @{ $download_results } );

    my $all_extra_sentences_total        = sum( map { $_->{ extra_sentences_total } } @{ $download_results } );
    my $all_extra_sentences_dedupped     = sum( map { $_->{ extra_sentences_dedupped } } @{ $download_results } );
    my $all_extra_sentences_not_dedupped = sum( map { $_->{ extra_sentences_not_dedupped } } @{ $download_results } );
    my $all_extra_sentences_missing      = sum( map { $_->{ extra_sentences_missing } } @{ $download_results } );

    my $all_missing_sentences_total        = sum( map { $_->{ missing_sentences_total } } @{ $download_results } );
    my $all_missing_sentences_dedupped     = sum( map { $_->{ missing_sentences_dedupped } } @{ $download_results } );
    my $all_missing_sentences_not_dedupped = sum( map { $_->{ missing_sentences_not_dedupped } } @{ $download_results } );
    my $all_missing_sentences_missing      = sum( map { $_->{ missing_sentences_missing } } @{ $download_results } );

    my $all_correctly_included_sentences_total =
      sum( map { $_->{ correctly_included_sentences_total } } @{ $download_results } );
    my $all_correctly_included_sentences_dedupped =
      sum( map { $_->{ correctly_included_sentences_dedupped } } @{ $download_results } );
    my $all_correctly_included_sentences_not_dedupped =
      sum( map { $_->{ correctly_included_sentences_not_dedupped } } @{ $download_results } );
    my $all_correctly_included_sentences_missing =
      sum( map { $_->{ correctly_included_sentences_missing } } @{ $download_results } );

    print "$errors errors / " . scalar( @downloads ) . " downloads\n";
    print "lines: $all_story_lines story / $all_extra_lines (" . $all_extra_lines / $all_story_lines .
      ") extra / $all_missing_lines (" . $all_missing_lines / $all_story_lines . ") missing\n";

    if ( $all_story_characters == 0 )
    {
        print "Error no story charcters\n";
    }
    else
    {
        print "characters: $all_story_characters story / $all_extra_characters (" .
          $all_extra_characters / $all_story_characters . ") extra / $all_missing_characters (" .
          $all_missing_characters / $all_story_characters . ") missing\n";
    }

    if ( $all_extra_sentences_total )
    {
        print " Extra sentences              : $all_extra_sentences_total\n";

        print " Extra sentences dedupped     : $all_extra_sentences_dedupped (" .
          ( $all_extra_sentences_dedupped / $all_extra_sentences_total ) . ")\n";
        print " Extra sentences not dedupped : $all_extra_sentences_not_dedupped (" .
          $all_extra_sentences_not_dedupped / $all_extra_sentences_total . ")\n";
        print " Extra sentences missing : $all_extra_sentences_missing (" .
          $all_extra_sentences_missing / $all_extra_sentences_total . ")\n";

    }

    if ( $all_correctly_included_sentences_total )
    {
        print " Correctly_Included sentences              : $all_correctly_included_sentences_total\n";

        print " Correctly_Included sentences dedupped     : $all_correctly_included_sentences_dedupped (" .
          ( $all_correctly_included_sentences_dedupped / $all_correctly_included_sentences_total ) . ")\n";
        print " Correctly_Included sentences not dedupped : $all_correctly_included_sentences_not_dedupped (" .
          $all_correctly_included_sentences_not_dedupped / $all_correctly_included_sentences_total . ")\n";
        print " Correctly_Included sentences missing : $all_correctly_included_sentences_missing (" .
          $all_correctly_included_sentences_missing / $all_correctly_included_sentences_total . ")\n";
    }

    if ( $all_missing_sentences_total )
    {
        print " Missing sentences              : $all_missing_sentences_total\n";

        print " Missing sentences dedupped     : $all_missing_sentences_dedupped (" .
          ( $all_missing_sentences_dedupped / $all_missing_sentences_total ) . ")\n";
        print " Missing sentences not dedupped : $all_missing_sentences_not_dedupped (" .
          $all_missing_sentences_not_dedupped / $all_missing_sentences_total . ")\n";
        print " Missing sentences missing : $all_missing_sentences_missing (" .
          $all_missing_sentences_missing / $all_missing_sentences_total . ")\n";

    }

}

# do a test run of the text extractor
sub main
{

    my $db = MediaWords::DB->authenticate();

    my $dbs = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'                  => \$file,
        'downloads|d=s'             => \@download_ids,
        'regenerate_database_cache' => \$_re_generate_cache,
    ) or die;

    my $downloads;

    if ( @download_ids )
    {
        $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    }
    elsif ( $file )
    {
        open( DOWNLOAD_ID_FILE, $file ) || die( "Could not open file: $file" );
        @download_ids = <DOWNLOAD_ID_FILE>;
        $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    }
    else
    {
        $downloads = $dbs->query(
"SELECT * from downloads where downloads_id in (select distinct downloads_id from extractor_training_lines order by downloads_id)"
        )->hashes;
    }

    extractAndScoreDownloads( $downloads );
}

main();
