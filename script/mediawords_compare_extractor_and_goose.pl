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
use HTML::Strip;
use MediaWords::Util::HTML;
use File::Slurp;
use IPC::Open2;
 use Time::HiRes qw( time );

my $_re_generate_cache = 0;

Readonly my $output_dir => 'download_content_test_data';
Readonly my $goose_dir  => '/home/dlarochelle/goose/goose';

my $expected_text_time = 0;
my $mc_extractor_time = 0;
my $goose_extractor_time = 0;

sub get_story_html_for_lines
{
    my ( $preprocessed_lines, $lines ) = @_;

    my $expected_story_lines = [ map { $preprocessed_lines->[ $_ ] } @{ $lines } ];

    my $expected_html = join "\n", @{ $expected_story_lines };

    return $expected_html;
}

sub get_story_text_for_lines
{
    my ( $preprocessed_lines, $lines ) = @_;

    my $expected_html = get_story_html_for_lines( $preprocessed_lines, $lines );

    my $expected_txt = html_strip( $expected_html );

    return $expected_txt;
}

my $goose_started = 0;

my ( $chld_out, $chld_in );

my $goose_pid;

sub start_goose
{
    my $system_command =
      "bash -c \"cd $goose_dir; mvn exec:java -Dexec.mainClass=com.gravity.goose.TalkToMeGoose -Dexec.args='' -e -q \"";

    say STDERR $system_command;

    $goose_pid = open2( $chld_out, $chld_in, $system_command );

    sleep 3;

    $goose_started = 1;
}

sub kill_goose
{

    say STDERR "killing goose";

    close ( $chld_in);

    sleep 1;
    kill( $goose_pid );
}

sub extract_with_goose
{
    my ( $content_ref, $url ) = @_;

    my $temp_dir = File::Temp::tempdir || die( "Unable to create temp dir" );

    say STDERR "Directory '$temp_dir'";

    Readonly my $raw_html_file => "$temp_dir/article.html";

    open( FILE, "> $raw_html_file" ) || die "$@";

    say FILE $$content_ref;

    close( FILE );

    my $extracted_text_file = "$temp_dir/output.txt";

    if ( !$goose_started )
    {
        start_goose();
    }

    say STDERR "sending goose url and file location: $url $raw_html_file";

    say $chld_in, "$url $raw_html_file" || die "$@";

    #system( $system_command );

    # my $extracted_text = read_file( $extracted_text_file );

    my $extracted_text;

    while ( my $line = <$chld_out> )
    {
        chomp( $line );

        #say STDERR "Got line'$line'";
        if ( $line eq 'ARTICLE DUMPED' )
        {
            last;
        }
        $extracted_text .= $line;
    }

    #$extracted_text =~ s/^\+ Error stacktraces are turned on\.//;

    say STDERR "got extracted_text from goose";

    #say STDERR "text: $extracted_text";

    #exit;
    return $extracted_text;
}

sub processDownload
{
    ( my $download, my $dbs ) = @_;

    my $errors = 0;

    say STDERR "processDownload: $download->{downloads_id}";

    my $expected_text_start_time = time();

    my $line_should_be_in_story = MediaWords::Util::ExtractorTest::get_lines_that_should_be_in_story( $download, $dbs );

    my @required_lines = grep { $line_should_be_in_story->{ $_ } eq 'required' } keys %{ $line_should_be_in_story };
    my @optional_lines = grep { $line_should_be_in_story->{ $_ } eq 'optional' } keys %{ $line_should_be_in_story };

    my $preprocessed_lines = MediaWords::Util::ExtractorTest::get_preprocessed_content_lines_for_download( $download );

    my $expected_story_txt = get_story_text_for_lines( $preprocessed_lines, [ keys %{ $line_should_be_in_story } ] );

    say STDERR "got expected story text for download $download->{downloads_id}";

    #say "Expected txt: $expected_story_txt\n";
    #exit;

    my $story_line_count = scalar( keys %{ $line_should_be_in_story } );

    $expected_text_time += time() - $expected_text_start_time;

    my $mc_extractor_start_time = time();

    my @extracted_lines =
      MediaWords::Util::ExtractorTest::get_extracted_lines_for_story( $download, $dbs, $preprocessed_lines,
        !$_re_generate_cache );

    my $extracted_story_txt = get_story_text_for_lines( $preprocessed_lines, \@extracted_lines );

    #say "extracted story txt: $extracted_story_txt\n";

    my $mc_similarity_score =
      Text::Similarity::Overlaps->new( { normalize => 1, verbose => 0 } )
      ->getSimilarityStrings( $expected_story_txt, $extracted_story_txt );

    say "Similarity score: $mc_similarity_score\n";

    $mc_extractor_time += time() - $mc_extractor_start_time;

    my $goose_extractor_start_time = time();

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $download );

    my $goose_extracted = extract_with_goose( $content_ref, $download->{ url } );

    #say "goose extracted txt: $goose_extracted";

    my $goose_similarity_score =
      Text::Similarity::Overlaps->new( { normalize => 1, verbose => 0 } )
      ->getSimilarityStrings( $expected_story_txt, $goose_extracted );

    my $ret = {
        mc_similarity_score    => $mc_similarity_score,
        goose_similarity_score => $goose_similarity_score
    };

    $goose_extractor_time += time() - $goose_extractor_start_time;

    say Dumper ( $ret );

    return $ret;
}

sub extractAndScoreDownloads
{

    my $downloads = shift;

    my @downloads = @{ $downloads };

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $download_results = [];

    my $dbs = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    start_goose();

    my $download_count = scalar(@downloads);

    my $downloads_processed = 0;
    for my $download ( @downloads )
    {
        my $download_result = processDownload( $download, $dbs );

        push( @{ $download_results }, $download_result );

	$downloads_processed++;
	say STDERR "processed $downloads_processed / $download_count downloads";
    }

    kill_goose();

    say STDERR Dumper( $download_results );

    my @mc_similarity_score = map { $_->{ mc_similarity_score } } @ { $download_results } ;
    my @goose_similarity_score = map { $_->{ goose_similarity_score } } @ { $download_results } ;


    my $mc_average_similarity_score = sum ( @mc_similarity_score ) / scalar( @mc_similarity_score );
    my $goose_average_similarity_score = sum ( @goose_similarity_score ) / scalar( @goose_similarity_score );

    say "Average Media Cloud simility score: $mc_average_similarity_score";
    say "Average Goose       simility score: $goose_average_similarity_score";

    say "Expected text time:  $expected_text_time ";
    say "Media Cloud extractor time: $mc_extractor_time";
    say "Goose extractor time : $goose_extractor_time";

    return;
    exit;

    # my $all_story_characters   = sum( map { $_->{ story_characters } } @{ $download_results } );
    # my $all_extra_characters   = sum( map { $_->{ extra_characters } } @{ $download_results } );
    # my $all_missing_characters = sum( map { $_->{ missing_characters } } @{ $download_results } );
    # my $all_story_lines        = sum( map { $_->{ story_line_count } } @{ $download_results } );
    # my $all_extra_lines        = sum( map { $_->{ extra_line_count } } @{ $download_results } );
    # my $all_missing_lines      = sum( map { $_->{ missing_line_count } } @{ $download_results } );
    # my $errors                 = sum( map { $_->{ errors } } @{ $download_results } );

    # my $all_extra_sentences_total        = sum( map { $_->{ extra_sentences_total } } @{ $download_results } );
    # my $all_extra_sentences_dedupped     = sum( map { $_->{ extra_sentences_dedupped } } @{ $download_results } );
    # my $all_extra_sentences_not_dedupped = sum( map { $_->{ extra_sentences_not_dedupped } } @{ $download_results } );
    # my $all_extra_sentences_missing      = sum( map { $_->{ extra_sentences_missing } } @{ $download_results } );

    # my $all_missing_sentences_total        = sum( map { $_->{ missing_sentences_total } } @{ $download_results } );
    # my $all_missing_sentences_dedupped     = sum( map { $_->{ missing_sentences_dedupped } } @{ $download_results } );
    # my $all_missing_sentences_not_dedupped = sum( map { $_->{ missing_sentences_not_dedupped } } @{ $download_results } );
    # my $all_missing_sentences_missing      = sum( map { $_->{ missing_sentences_missing } } @{ $download_results } );

    # my $all_correctly_included_sentences_total =
    #   sum( map { $_->{ correctly_included_sentences_total } } @{ $download_results } );
    # my $all_correctly_included_sentences_dedupped =
    #   sum( map { $_->{ correctly_included_sentences_dedupped } } @{ $download_results } );
    # my $all_correctly_included_sentences_not_dedupped =
    #   sum( map { $_->{ correctly_included_sentences_not_dedupped } } @{ $download_results } );
    # my $all_correctly_included_sentences_missing =
    #   sum( map { $_->{ correctly_included_sentences_missing } } @{ $download_results } );

    # print "$errors errors / " . scalar( @downloads ) . " downloads\n";
    # print "lines: $all_story_lines story / $all_extra_lines (" . $all_extra_lines / $all_story_lines .
    #   ") extra / $all_missing_lines (" . $all_missing_lines / $all_story_lines . ") missing\n";

    # if ( $all_story_characters == 0 )
    # {
    #     print "Error no story charcters\n";
    # }
    # else
    # {
    #     print "characters: $all_story_characters story / $all_extra_characters (" .
    #       $all_extra_characters / $all_story_characters . ") extra / $all_missing_characters (" .
    #       $all_missing_characters / $all_story_characters . ") missing\n";
    # }

    # if ( $all_extra_sentences_total )
    # {
    #     print " Extra sentences              : $all_extra_sentences_total\n";

    #     print " Extra sentences dedupped     : $all_extra_sentences_dedupped (" .
    #       ( $all_extra_sentences_dedupped / $all_extra_sentences_total ) . ")\n";
    #     print " Extra sentences not dedupped : $all_extra_sentences_not_dedupped (" .
    #       $all_extra_sentences_not_dedupped / $all_extra_sentences_total . ")\n";
    #     print " Extra sentences missing : $all_extra_sentences_missing (" .
    #       $all_extra_sentences_missing / $all_extra_sentences_total . ")\n";

    # }

    # if ( $all_correctly_included_sentences_total )
    # {
    #     print " Correctly_Included sentences              : $all_correctly_included_sentences_total\n";

    #     print " Correctly_Included sentences dedupped     : $all_correctly_included_sentences_dedupped (" .
    #       ( $all_correctly_included_sentences_dedupped / $all_correctly_included_sentences_total ) . ")\n";
    #     print " Correctly_Included sentences not dedupped : $all_correctly_included_sentences_not_dedupped (" .
    #       $all_correctly_included_sentences_not_dedupped / $all_correctly_included_sentences_total . ")\n";
    #     print " Correctly_Included sentences missing : $all_correctly_included_sentences_missing (" .
    #       $all_correctly_included_sentences_missing / $all_correctly_included_sentences_total . ")\n";
    # }

    # if ( $all_missing_sentences_total )
    # {
    #     print " Missing sentences              : $all_missing_sentences_total\n";

    #     print " Missing sentences dedupped     : $all_missing_sentences_dedupped (" .
    #       ( $all_missing_sentences_dedupped / $all_missing_sentences_total ) . ")\n";
    #     print " Missing sentences not dedupped : $all_missing_sentences_not_dedupped (" .
    #       $all_missing_sentences_not_dedupped / $all_missing_sentences_total . ")\n";
    #     print " Missing sentences missing : $all_missing_sentences_missing (" .
    #       $all_missing_sentences_missing / $all_missing_sentences_total . ")\n";

    # }

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

    kill( $goose_pid );
}

main();
