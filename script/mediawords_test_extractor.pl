#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

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
use MediaWords::DBI::Downloads;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use Lingua::EN::Sentence::MediaWords;
use Perl6::Say;
use Data::Dumper;
use MediaWords::Util::HTML;

my $_re_generate_cache = 0;

sub text_length
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

sub get_extractor_scores_for_lines
{
    ( my $lines, my $story_title, my $story_description, my $download, my $dbs ) = @_;

    my $ret;

    if ( !$_re_generate_cache )
    {
        $ret = get_cached_extractor_line_scores( $download, $dbs );
    }

    if ( !defined( $ret ) || !@{ $ret } )
    {
        $ret = MediaWords::Crawler::Extractor::score_lines( $lines, $story_title, $story_description, );
        store_extractor_line_scores( $ret, $lines, $download, $dbs );
    }
    return $ret;
}

#returns the sum of the string length for each line the training table says should be in the story.
sub get_character_count_for_story
{
    ( my $download, my $line_should_be_in_story ) = @_;
    my $lines = get_preprocessed_content_lines_for_download( $download );
    my $story_characters = sum( map { text_length( $lines->[ $_ ] ) } keys %{ $line_should_be_in_story } );

    return $story_characters;
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

sub processDownload
{
    ( my $download, my $dbs ) = @_;

    my $errors = 0;

    my $line_should_be_in_story = get_lines_that_should_be_in_story( $download, $dbs );

    my @required_lines = grep { $line_should_be_in_story->{ $_ } eq 'required' } keys %{ $line_should_be_in_story };
    my @optional_lines = grep { $line_should_be_in_story->{ $_ } eq 'optional' } keys %{ $line_should_be_in_story };

    my $preprocessed_lines = get_preprocessed_content_lines_for_download( $download );

    my $story_line_count = scalar( keys %{ $line_should_be_in_story } );

    my $story_title =
      $dbs->query( "SELECT title FROM stories where stories.stories_id=? ", $download->{ stories_id } )->flat->[ 0 ];
    my $story_description =
      $dbs->query( "SELECT description FROM stories where stories.stories_id=? ", $download->{ stories_id } )->flat->[ 0 ];

    my $scores = [];

    $scores = get_extractor_scores_for_lines( $preprocessed_lines, $story_title, $story_description, $download, $dbs );

    my @extracted_lines = map { $_->{ line_number } } grep { $_->{ is_story } } @{ $scores };

    my @missing_lines = get_unique( [ \@required_lines, \@extracted_lines ] );
    my @extra_lines = get_unique( [ \@extracted_lines, get_union_ref( [ \@required_lines, \@optional_lines ] ) ] );

    my $story_characters = get_character_count_for_story( $download, $line_should_be_in_story );

    my $download_errors;

    my $missing_characters = 0;

    for my $missing_line_number ( @missing_lines )
    {
        $missing_characters += text_length( $preprocessed_lines->[ $missing_line_number ] );

        $download_errors .= "missing line $missing_line_number: " . $preprocessed_lines->[ $missing_line_number ] . "\n";
    }
    my $extra_characters = 0;

    for my $extra_line_number ( @extra_lines )
    {
        $extra_characters += text_length( $preprocessed_lines->[ $extra_line_number ] );
        $download_errors .= "extra line $extra_line_number: " . $preprocessed_lines->[ $extra_line_number ] . "\n";
    }

    my $extra_sentences_total        = 0;
    my $extra_sentences_dedupped     = 0;
    my $extra_sentences_not_dedupped = 0;
    my $extra_sentences_missing      = 0;

    my $story = $dbs->find_by_id( 'stories', $download->{ stories_id } );
    say Dumper( $story );


    for my $extra_line_number ( @extracted_lines )
    {
        my $line_text = $preprocessed_lines->[ $extra_line_number ];

	say "Line text: $line_text";

	$line_text = html_strip( $line_text);

	say "Line text no html: $line_text";

        my $sentences = Lingua::EN::Sentence::MediaWords::get_sentences( $line_text );

        foreach my $sentence ( @{ $sentences } )
        {

	    $sentence = html_strip( $sentence )
;
	    say "Sentence: '$sentence'";

            my $dup_sentence = $dbs->query(
                "select * from story_sentence_counts " .
                  "  where sentence_md5 = md5( ? ) and media_id = ? and publish_week = date_trunc( 'week', ?::date )" .
                  "  order by story_sentence_counts_id limit 1",
                $sentence,
                $story->{ media_id },
                $story->{ publish_date }
            )->hash;

            $extra_sentences_total++;

            if ( $dup_sentence )
            {
                if ( $dup_sentence->{ count } <= 1 )
                {
                    $extra_sentences_not_dedupped++;
                }
                else
                {
                    $extra_sentences_dedupped++;
                }
            }
            else
            {
                $extra_sentences_missing++;
            }
        }

    }

    if ( $download_errors )
    {
        my $story_title =
          $dbs->query( "SELECT title FROM stories where stories.stories_id=? ", $download->{ stories_id } )->flat->[ 0 ];

        print "****\nerrors in download " . $download->{ downloads_id } . ": " . $story_title . "\n" .
          "$download_errors\n****\n";
        $errors++;
    }

    my $extra_line_count   = scalar( @extra_lines );
    my $missing_line_count = scalar( @missing_lines );

    my $ret = {
        story_characters   => $story_characters,
        story_line_count   => $story_line_count,
        extra_line_count   => $extra_line_count,
        missing_line_count => $missing_line_count,
        extra_characters   => $extra_characters,
        errors             => $errors,
        missing_characters => $missing_characters,
        accuracy           => (
            $story_characters
            ? int( ( $extra_characters + $missing_characters ) / $story_characters * 100 )
            : 0
        ),
        extra_sentences_total        => $extra_sentences_total,
        extra_sentences_dedupped     => $extra_sentences_dedupped,
        extra_sentences_not_dedupped => $extra_sentences_not_dedupped,
        extra_sentences_missing      => $extra_sentences_missing,
    };

    say Dumper( $ret );
    return $ret;
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

    my $all_story_characters   = sum( map { $_->{ story_characters } } @{ $download_results } );
    my $all_extra_characters   = sum( map { $_->{ extra_characters } } @{ $download_results } );
    my $all_missing_characters = sum( map { $_->{ missing_characters } } @{ $download_results } );
    my $all_story_lines        = sum( map { $_->{ story_line_count } } @{ $download_results } );
    my $all_extra_lines        = sum( map { $_->{ extra_line_count } } @{ $download_results } );
    my $all_missing_lines      = sum( map { $_->{ missing_line_count } } @{ $download_results } );
    my $errors                 = sum( map { $_->{ errors } } @{ $download_results } );

    my $all_extra_sentences_total        = sum( map { $_->{ extra_sentences_total } } @{ $download_results } );
    my $all_extra_sentences_dedupped     = sum( map { $_->{ extra_sentences_depudded } } @{ $download_results } );
    my $all_extra_sentences_not_dedupped = sum( map { $_->{ extra_sentences_not_depudded } } @{ $download_results } );
    my $all_extra_sentences_missing      = sum( map { $_->{ extra_sentences_missing } } @{ $download_results } );

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
          ( $all_extra_sentences_dedupped / $all_extra_sentences_total ) . ")\n" ;
        print " Extra sentences not dedupped : $all_extra_sentences_dedupped (" .
          $all_extra_sentences_not_dedupped / $all_extra_sentences_total . ")\n";
        print " Extra sentences missing : $all_extra_sentences_missing (" .
          $all_extra_sentences_missing / $all_extra_sentences_total . ")\n" ;

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
