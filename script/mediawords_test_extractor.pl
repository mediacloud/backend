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
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::MoreUtils qw( :all);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );

use Data::Dumper;
use MediaWords::Util::HTML;
use MediaWords::Util::ExtractorTest;
use MediaWords::Util::HeuristicExtractor;
use MediaWords::Util::CrfExtractor;

use Data::Compare;
use Storable;
use 5.14.2;

my $_re_generate_cache = 0;
my $_test_sentences    = 0;

my $_download_data_load_file;
my $_download_data_store_file;
my $_dont_store_preprocessed_lines;
my $_dump_training_data_csv;

sub get_story_level_extractor_results
{
    my ( $download, $line_should_be_in_story, $missing_lines, $extra_lines, $correctly_included_lines, $preprocessed_lines,
        $dbs )
      = @_;

    my $story = $dbs->find_by_id( 'stories', $download->{ stories_id } );

    #say Dumper( $story );

    my $extra_line_sentence_info =
      MediaWords::Util::ExtractorTest::get_sentence_info_for_lines( $extra_lines, $preprocessed_lines, $story, $dbs );

    my $extra_sentences_dedupped     = $extra_line_sentence_info->{ sentences_dupped };
    my $extra_sentences_not_dedupped = $extra_line_sentence_info->{ sentences_not_dupped };
    my $extra_sentences_missing      = $extra_line_sentence_info->{ sentences_missing };

    my $extra_sentences_total = $extra_line_sentence_info->{ sentences_total };

    my $correctly_included_line_sentence_info =
      MediaWords::Util::ExtractorTest::get_sentence_info_for_lines( $correctly_included_lines, $preprocessed_lines, $story,
        $dbs );

    my $correctly_included_sentences_dedupped     = $correctly_included_line_sentence_info->{ sentences_dupped };
    my $correctly_included_sentences_not_dedupped = $correctly_included_line_sentence_info->{ sentences_not_dupped };
    my $correctly_included_sentences_missing      = $correctly_included_line_sentence_info->{ sentences_missing };

    my $correctly_included_sentences_total = $correctly_included_line_sentence_info->{ sentences_total };

    my $missing_line_sentence_info =
      MediaWords::Util::ExtractorTest::get_sentence_info_for_lines( $missing_lines, $preprocessed_lines, $story, $dbs );

    my $missing_sentences_dedupped     = $missing_line_sentence_info->{ sentences_dupped };
    my $missing_sentences_not_dedupped = $missing_line_sentence_info->{ sentences_not_dupped };
    my $missing_sentences_missing      = $missing_line_sentence_info->{ sentences_missing };

    my $missing_sentences_total = $missing_line_sentence_info->{ sentences_total };

    my $ret = {
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

sub analyze_download
{
    my ( $download, $dbs ) = @_;
    my $preprocessed_lines = MediaWords::Util::ExtractorTest::get_preprocessed_content_lines_for_download( $dbs, $download );

    my $line_info = MediaWords::Util::ExtractorTest::get_line_analysis_info( $download, $dbs, $preprocessed_lines );

    my $line_should_be_in_story = MediaWords::Util::ExtractorTest::get_lines_that_should_be_in_story( $download, $dbs );

    my $ret = {
        download                => $download,
        line_info               => $line_info,
        preprocessed_lines      => $preprocessed_lines,
        line_should_be_in_story => $line_should_be_in_story,
    };

    return $ret;
}

sub processDownload
{
    ( my $analyzed_download, my $dbs ) = @_;

    my $download           = $analyzed_download->{ download };
    my $line_info          = $analyzed_download->{ line_info };
    my $preprocessed_lines = $analyzed_download->{ preprocessed_lines };

    my $line_should_be_in_story = $analyzed_download->{ line_should_be_in_story };

    my $extracted_lines;

    my $extraction_method = 'Heuristic';

    # $extraction_method = 'old';

    my $extractor = MediaWords::Util::ExtractorFactory::createExtractor();

    $extracted_lines = $extractor->getExtractedLines( $line_info, $preprocessed_lines );

    return MediaWords::Util::ExtractorTest::compare_extraction_with_training_data( $line_should_be_in_story,
        $extracted_lines, $download, $preprocessed_lines, $dbs, $line_info, $_test_sentences );
}

sub analyze_downloads
{
    my ( $downloads ) = @_;

    my @downloads = @{ $downloads };

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $dbs = MediaWords::DB::connect_to_db();

    my $analyzed_downloads = [];

    for my $download ( @downloads )
    {
        my $download_result = analyze_download( $download, $dbs );

        push( @{ $analyzed_downloads }, $download_result );
    }

    return $analyzed_downloads;
}

sub dump_training_data_csv
{
    my ( $analyzed_downloads ) = @_;

    say "starting dump_training_data_csv";

    say "shuffling analyzed_downloads";

    srand( 12345 );

    $analyzed_downloads = [ shuffle @{ $analyzed_downloads } ];

    say " dump_training_data_csv add line should be in story";

    foreach my $analyzed_download ( @{ $analyzed_downloads } )
    {

        my $line_info = $analyzed_download->{ line_info };

        my $line_should_be_in_story = $analyzed_download->{ line_should_be_in_story };

        my $downloads_id = $analyzed_download->{ download }->{ downloads_id };
        foreach my $line ( @{ $line_info } )
        {
            $line->{ in_story } = defined( $line_should_be_in_story->{ $line->{ line_number } } ) ? 1 : 0;
            $line->{ training_result } = $line_should_be_in_story->{ $line->{ line_number } } // 'exclude';
            $line->{ downloads_id } = $downloads_id;
        }

    }

    say " dump_training_data_csv creating all_line_infos";

    #$analyzed_downloads =  [ ( @{ $analyzed_downloads } [ 0 ... 2000 ] ) ];

    my @all_line_infos = map { @{ $_->{ line_info } } } ( @{ $analyzed_downloads } );

    #say Dumper ( [ @all_line_infos ] );

    say " dump_training_data_csv creating lines_not_autoexcluded";

    my @lines_not_autoexcluded = grep { !$_->{ auto_excluded } } @all_line_infos;

    #say Dumper ( [ @lines_not_autoexcluded ] );

    use Class::CSV;

    my $first_line = [ @lines_not_autoexcluded ]->[ 0 ];

    my $fields = [ keys %{ $first_line } ];

    my $csv = Class::CSV->new(
        fields         => $fields,
        line_separator => "\r\n",
    );

    $csv->add_line( $fields );

    foreach my $line_not_autoexcluded ( @lines_not_autoexcluded )
    {
        $csv->add_line( $line_not_autoexcluded );
    }

    Readonly my $training_data_csv_filename => '/tmp/training_data.csv';

    open( my $csv_fh, '>', $training_data_csv_filename ) or die "cannot open > $training_data_csv_filename: $!";

    say $csv_fh $csv->string();

    say STDERR "CSV dump complete";

    exit;
}

sub extractAndScoreDownloads
{
    my $downloads = shift;

    my $analyzed_downloads = [];

    if ( defined( $_download_data_load_file ) )
    {
        say STDERR "reading datafile $_download_data_load_file ";
        $analyzed_downloads = retrieve( $_download_data_load_file ) || die;
        say STDERR "read datafile $_download_data_load_file ";
    }
    else
    {
        $analyzed_downloads = analyze_downloads( $downloads );
    }

    if ( defined( $_dump_training_data_csv ) )
    {
        dump_training_data_csv( $analyzed_downloads );
    }

    if ( $_download_data_store_file )
    {
        my $preprocessed_lines_tmp;

        if ( $_dont_store_preprocessed_lines )
        {
            foreach my $analyzed_download ( @$analyzed_downloads )
            {
                push @{ $preprocessed_lines_tmp }, $analyzed_download->{ preprocessed_lines };
                undef( $analyzed_download->{ preprocessed_lines } );
            }
        }

        store( $analyzed_downloads, $_download_data_store_file );

        if ( defined( $preprocessed_lines_tmp ) )
        {
            foreach my $analyzed_download ( @$analyzed_downloads )
            {
                $analyzed_download->{ preprocessed_lines } = shift @{ $preprocessed_lines_tmp };
            }
        }
    }

    my $download_results = [];

    my $dbs = MediaWords::DB::connect_to_db();

    for my $analyzed_download ( @$analyzed_downloads )
    {
        my $download_result = processDownload( $analyzed_download, $dbs );

        push( @{ $download_results }, $download_result );
    }

    process_download_results( $download_results );
}

sub process_download_results
{
    my ( $download_results, $download_count ) = @_;

    #say STDERR Dumper( $download_results );

    my $all_story_characters   = sum( map { $_->{ story_characters } } @{ $download_results } );
    my $all_extra_characters   = sum( map { $_->{ extra_characters } } @{ $download_results } );
    my $all_missing_characters = sum( map { $_->{ missing_characters } } @{ $download_results } );
    my $all_story_lines        = sum( map { $_->{ story_line_count } } @{ $download_results } );
    my $all_extra_lines        = sum( map { $_->{ extra_line_count } } @{ $download_results } );
    my $all_missing_lines      = sum( map { $_->{ missing_line_count } } @{ $download_results } );
    my $errors                 = sum( map { $_->{ errors } } @{ $download_results } );

    my $non_optional_non_autoexclude_line_count =
      sum( map { $_->{ non_optional_non_autoexclude_line_count } } @{ $download_results } );

    print "$errors errors / " . scalar( @$download_results ) . " downloads\n";
    print "story lines: $all_story_lines story / $all_extra_lines (" . $all_extra_lines / $all_story_lines .
      ") extra / $all_missing_lines (" . $all_missing_lines / $all_story_lines . ") missing\n";

    my $precision = ( $all_story_lines - $all_missing_lines ) / ( $all_story_lines - $all_missing_lines + $all_extra_lines );
    say
"Precision: $precision = ( $all_story_lines - $all_missing_lines ) / ( $all_story_lines - $all_missing_lines + $all_extra_lines );";

    my $recall = ( $all_story_lines - $all_missing_lines ) / $all_story_lines;
    say "Recall: $recall -- ( $all_story_lines - $all_missing_lines ) / $all_story_lines ";

    print "non_ignoreable lines: $non_optional_non_autoexclude_line_count / $all_extra_lines (" .
      $all_extra_lines / $non_optional_non_autoexclude_line_count .
      ") extra / $all_missing_lines (" . $all_missing_lines / $non_optional_non_autoexclude_line_count . ") missing\t";

    say "correct: " . ( 1.0 - ( ( $all_extra_lines + $all_missing_lines ) / $non_optional_non_autoexclude_line_count ) );

    if ( $all_story_characters == 0 )
    {
        print "Error no story charcters\n";
    }
    else
    {
        print "characters: $all_story_characters story / $all_extra_characters (" .
          $all_extra_characters / $all_story_characters .
          ") extra / $all_missing_characters (" . $all_missing_characters / $all_story_characters . ") missing\n";
    }

    if ( $_test_sentences )
    {
        my $all_extra_sentences_total        = sum( map { $_->{ extra_sentences_total } } @{ $download_results } );
        my $all_extra_sentences_dedupped     = sum( map { $_->{ extra_sentences_dedupped } } @{ $download_results } );
        my $all_extra_sentences_not_dedupped = sum( map { $_->{ extra_sentences_not_dedupped } } @{ $download_results } );
        my $all_extra_sentences_missing      = sum( map { $_->{ extra_sentences_missing } } @{ $download_results } );

        my $all_missing_sentences_total    = sum( map { $_->{ missing_sentences_total } } @{ $download_results } );
        my $all_missing_sentences_dedupped = sum( map { $_->{ missing_sentences_dedupped } } @{ $download_results } );
        my $all_missing_sentences_not_dedupped =
          sum( map { $_->{ missing_sentences_not_dedupped } } @{ $download_results } );
        my $all_missing_sentences_missing = sum( map { $_->{ missing_sentences_missing } } @{ $download_results } );

        my $all_correctly_included_sentences_total =
          sum( map { $_->{ correctly_included_sentences_total } } @{ $download_results } );
        my $all_correctly_included_sentences_dedupped =
          sum( map { $_->{ correctly_included_sentences_dedupped } } @{ $download_results } );
        my $all_correctly_included_sentences_not_dedupped =
          sum( map { $_->{ correctly_included_sentences_not_dedupped } } @{ $download_results } );
        my $all_correctly_included_sentences_missing =
          sum( map { $_->{ correctly_included_sentences_missing } } @{ $download_results } );

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

}

# do a test run of the text extractor
sub main
{

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'                      => \$file,
        'downloads|d=s'                 => \@download_ids,
        'regenerate_database_cache'     => \$_re_generate_cache,
        'test_sentences'                => \$_test_sentences,
        'download_data_load_file=s'     => \$_download_data_load_file,
        'download_data_store_file=s'    => \$_download_data_store_file,
        'dont_store_preprocessed_lines' => \$_dont_store_preprocessed_lines,
        'dump_training_data_csv'        => \$_dump_training_data_csv,
    ) or die;

    my $downloads;

    if ( !$_download_data_load_file )
    {

        my $db = MediaWords::DB->authenticate();

        my $dbs = MediaWords::DB::connect_to_db();

        if ( @download_ids )
        {
            $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
        }
        elsif ( $file )
        {
            open( DOWNLOAD_ID_FILE, $file ) || die( "Could not open file: $file" );
            @download_ids = <DOWNLOAD_ID_FILE>;
	    #say Dumper ( [ @download_ids ] );
            $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
        }
        else
        {
            $downloads = $dbs->query(
"SELECT * from downloads where downloads_id in (select distinct downloads_id from extractor_training_lines order by downloads_id)"
            )->hashes;
        }
    }

    extractAndScoreDownloads( $downloads );
}

main();
