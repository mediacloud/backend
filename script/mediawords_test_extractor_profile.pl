#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;

# do a test run of the text extractor
sub main
{

    my $db = MediaWords::DB->connect_to_db();

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'      => \$file,
        'downloads|d=s' => \@download_ids
    ) or die;

    my @downloads;

    if ( @download_ids )
    {
        @downloads =
          $db->resultset( 'Downloads' )
          ->search( {}, { where => 'me.downloads_id in (' . join( ",", @download_ids ) . ')' } );
    }
    elsif ( $file )
    {

        #TODO we should really validate the file or escape the lines. Building our own SQL statement is bad.
        open( DOWNLOAD_ID_FILE, $file ) || die( "Could not open file: $file" );
        @download_ids = <DOWNLOAD_ID_FILE>;
        @downloads =
          $db->resultset( 'Downloads' )
          ->search( {}, { where => 'me.downloads_id in (' . join( ",", @download_ids ) . ')' } );
    }
    else
    {
        @downloads = $db->resultset( 'Downloads' )->search(
            {},
            {
                where =>
'me.downloads_id in (select distinct downloads_id from extractor_training_lines order by downloads_id limit 60)',
            }
        );
    }

    extractAndScoreDownloads( $db, \@downloads );

}

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

sub extractAndScoreDownloads($$)
{

    my ( $db, $downloads ) = @_;

    my @downloads = @{ $downloads };

    @downloads = sort { $a->downloads_id <=> $b->downloads_id } @downloads;

    my $errors           = 0;
    my $download_results = [];
    my ( $all_story_characters, $all_extra_characters, $all_missing_characters );

    my ( $all_story_lines, $all_extra_lines, $all_missing_lines );

    for my $download ( @downloads )
    {
        my ( $story_characters, $extra_characters, $missing_characters );

        my ( $story_line_count, $extra_line_count, $missing_line_count );

        my $lines = MediaWords::DBI::Downloads::fetch_preprocessed_content_lines( $db, $download );

        my $scores = MediaWords::Crawler::Extractor::score_lines(
            $lines,
            $download->stories_id->title,
            $download->stories_id->description
        );

        my @story_lines = $download->extractor_training_lines;
        my $line_is_story;
        for my $story_line ( @story_lines )
        {
            print "story_line: " . $story_line->line_number . "\n";
            $line_is_story->{ $story_line->line_number } = $story_line->required ? 'required' : 'optional';
            $story_characters += text_length( $lines->[ $story_line->line_number ] );
            $story_line_count++;
        }

        my $extra_lines   = [];
        my $missing_lines = [];
        my $download_errors;
        my $story_text;
        for ( my $i = 0 ; $i < @{ $scores } ; $i++ )
        {
            my $score = $scores->[ $i ];
            my $error_tag =
              "\n [" . $i . ' / ' . $score->{ html_density } . ' / ' . $score->{ discounted_html_density } . ']';
            if ( $score->{ is_story } && !$line_is_story->{ $i } )
            {
                $extra_characters += text_length( $lines->[ $i ] );
                $extra_line_count++;
                $download_errors .= "extra: " . $lines->[ $i ] . $error_tag . "\n";
            }
            elsif ( !$score->{ is_story }
                && ( $line_is_story->{ $i } eq 'required' ) )
            {
                $missing_characters += text_length( $lines->[ $i ] );
                $missing_line_count++;

                $download_errors .= "missing: " . $lines->[ $i ] . $error_tag . "\n";
            }

            if ( $score->{ is_story } )
            {
                $story_text .= $lines->[ $i ];
            }
        }

        if ( $download_errors )
        {
            print "****\nerrors in download " .
              $download->downloads_id . ": " . $download->stories_id->title . "\n" . "$download_errors\n****\n";
            $errors++;
        }

        push(
            @{ $download_results },
            {
                story_characters   => $story_characters   || 0,
                extra_characters   => $extra_characters   || 0,
                missing_characters => $missing_characters || 0,
                accuracy           => $story_characters
                ? int( ( $extra_characters + $missing_characters ) / $story_characters * 100 )
                : 0
            }
        );

        $all_story_characters   += $story_characters;
        $all_extra_characters   += $extra_characters;
        $all_missing_characters += $missing_characters;

        $all_story_lines   += $story_line_count;
        $all_extra_lines   += $extra_line_count;
        $all_missing_lines += $missing_line_count;

        #print "story text:\n****\n$story_text\n****\n";
    }

    my $sorted_download_results = [ sort { $a->{ accuracy } <=> $b->{ accuracy } } @{ $download_results } ];

    for ( my $i = 0 ; $i < @{ $sorted_download_results } ; $i++ )
    {
        my $r = $sorted_download_results->[ $i ];

        print "$i: ";
        print $r->{ accuracy } . " ";

        print $r->{ story_characters } . " ";
        print $r->{ extra_characters } . " ";
        print $r->{ missing_characters } . "\n";
    }

    print "$errors errors / " . scalar( @downloads ) . " downloads\n";
    print "lines: $all_story_lines story / $all_extra_lines (" . $all_extra_lines / $all_story_lines .
      ") extra / $all_missing_characters (" . $all_missing_lines / $all_story_lines . ") missing\n";

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
}

main();
