#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

my $cwd;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    $cwd = "$FindBin::Bin";
}

use Devel::SizeMe qw ( :all );
use Devel::SizeMe;

$Devel::SizeMe::do_size_at_end = 1;

use Readonly;

use Test::More;
require Test::NoWarnings;

use MediaWords::Crawler::Extractor qw (preprocess);
use DBIx::Simple::MediaWords;
use MediaWords::DBI::Downloads;
use MediaWords::DB;
use MediaWords::DBI::DownloadTexts;
use XML::LibXML;
use Encode;
use MIME::Base64;
use Carp qw (confess);
use Data::Dumper;
use MediaWords::Util::HTML;

Readonly my $output_dir => "$cwd/download_content_test_data";

print "$output_dir\n";

sub get_value_of_node
{
    my ( $root, $nodeName ) = @_;

    die if !( $root->getElementsByTagName( $nodeName ) )[ 0 ];
    confess if !( $root->getElementsByTagName( $nodeName ) )[ 0 ]->firstChild;

    my $value = ( $root->getElementsByTagName( $nodeName ) )[ 0 ]->firstChild->nodeValue;

    return $value;

}

sub get_value_of_base_64_node
{
    my ( $root, $nodeName ) = @_;
    my $value = get_value_of_node( $root, $nodeName );

    my $base_64_decoded_value = decode_base64( $value );

    my $ret = decode( "utf8", $base_64_decoded_value );

    return $ret;
}

use constant LEAK => 0;

use constant DESCRIPTION_SIMILARITY_DISCOUNT => .5;

sub get_description_similarity_discount
{
    my ( $line, $description ) = @_;

    # my $stripped_line        = html_strip( $line );
    # my $stripped_description = html_strip( $description );

    my $stripped_line        = "$line ";
    my $stripped_description = " $description ";

    my $score;

    if ( LEAK )
    {
        $score =
          Text::Similarity::Overlaps->new( { normalize => 1, verbose => 0 } )
          ->getSimilarityStrings( $stripped_line, $stripped_description );
    }
    else
    {
        my $sim = Text::Similarity::Overlaps->new( { normalize => 1, verbose => 0 } );

        $score = $sim->getSimilarityStrings( $stripped_line, $stripped_description );
    }

    my $power = 1 / DESCRIPTION_SIMILARITY_DISCOUNT;

    # 1 means complete similarity and 0 means none
    # so invert it
    return ( ( ( 1 - $score ) )**$power ) + 0.0;
}

sub _do_extraction_from_content_ref
{
    my ( $content_ref, $title, $description ) = @_;

    my @lines = split( /[\n\r]+/, $$content_ref );

    my $lines = MediaWords::Crawler::Extractor::preprocess( \@lines );

    my $ret = MediaWords::DBI::Downloads::extract_preprocessed_lines_for_story( $lines, $title, $description );

    return $ret;
}

sub my_extract_preprocessed_lines_for_story
{
    my ( $lines, $story_title, $story_description ) = @_;

    #my $scores = MediaWords::Crawler::Extractor::score_lines( $lines, $story_title, $story_description );

    MediaWords::Crawler::Extractor::score_lines( $lines, $story_title, $story_description );

    #my $included_line_numbers = MediaWords::DBI::Downloads::_get_included_line_numbers( $scores );

    #my $extracted_html =  get_extracted_html( $lines, $included_line_numbers );

    # return {

    #     #extracted_html => $extracted_html,
    #     #extracted_text => html_strip( $extracted_html ),
    #     #included_line_numbers => $included_line_numbers,
    #     download_lines        => $lines,
    #     scores                => $scores,
    # };
}

sub _wrappered_extract_preprocessed_lines_for_story
{
    my ( $lines, $title, $description ) = @_;

    my $ret = my_extract_preprocessed_lines_for_story( $lines, $title, $description );

    #my $ret =  MediaWords::DBI::Downloads::extract_preprocessed_lines_for_story( $lines, $title, $description );

    return $ret;
}

sub _heuristically_scored_lines_impl
{
    my ( $lines, $title, $description ) = @_;

    # use Data::Dumper;
    # die ( Dumper( @_ ) );

    #print_time( "score_lines" );

    #if ( !defined( $lines ) )
    #{
    #    return;
    #}

    #my $info_for_lines = MediaWords::Crawler::AnalyzeLines::get_info_for_lines( $lines, $title, $description );
    my $info_for_lines = get_info_for_lines( $lines, $title, $description );

    #MediaWords::Crawler::AnalyzeLines::get_info_for_lines( $lines, $title, $description );

    #my $scores = MediaWords::Crawler::HeuristicLineScoring::_score_lines_with_line_info( $info_for_lines );

    #$info_for_lines = 0;

    #return $scores;
}

sub get_info_for_lines_inner_loop
{
    my ( $info_for_lines, $lines, $title_text, $description, $sphereit_map, $has_clickprint, $auto_excluded_lines, $markers )
      = @_;

    my $line = defined( $lines->[ 0 ] ) ? $lines->[ 0 ] : '';

    my $line_info =
      MediaWords::Crawler::AnalyzeLines::calculate_full_line_metrics( $line, 0, $title_text, $description, $sphereit_map,
        $has_clickprint, $auto_excluded_lines, $markers );

    # $info_for_lines->[ 0 ] = $line_info;

    # for ( my $i = 0 ; $i < @{ $lines } ; $i++ )
    # {
    #     my $line = defined( $lines->[ $i ] ) ? $lines->[ $i ] : '';

    #     # $line =~ s/^\s*//;
    #     # $line =~ s/\s*$//;
    #     # $line =~ s/\s+/ /;

    #     #        print STDERR "line: $line" . "\n";

    #     my $score;

    #     my ( $html_density, $discounted_html_density, $explanation );

#     my $line_info = MediaWords::Crawler::AnalyzeLines::calculate_full_line_metrics( $line, $i, $title_text, $description, $sphereit_map, $has_clickprint,
#         $auto_excluded_lines, $markers );

    #     $info_for_lines->[ $i ] = $line_info;

    # 	last;
    # }

}

sub get_info_for_lines
{
    my ( $lines, $title, $description ) = @_;

    my $auto_excluded_lines =

      MediaWords::Crawler::Extractor::find_auto_excluded_lines( $lines );

    my $info_for_lines = [];

    #my $title_text = html_strip( $title );

    my $title_text = $title;
    $title_text =~ s/^\s*//;

    #$title_text =~ s/\s*$//;
    #$title_text =~ s/\s+/ /;

    my $markers        = MediaWords::Crawler::Extractor::find_markers( $lines );
    my $has_clickprint = HTML::CruftText::has_clickprint( $lines );
    my $sphereit_map   = MediaWords::Crawler::Extractor::get_sphereit_map( $markers );

    #MediaWords::Crawler::Extractor::print_time( "find_markers" );

    while ( 1 )
    {
        get_info_for_lines_inner_loop( $info_for_lines, $lines, $title_text, $description, $sphereit_map, $has_clickprint,
            $auto_excluded_lines, $markers );

    }

    undef( $markers );
    undef( $has_clickprint );
    undef( $sphereit_map );

    my $auto_excluded_lines = 0;

    #return $info_for_lines;
}

sub calculate_full_line_metrics
{
    my ( $line, $line_number, $title_text, $description, $sphereit_map, $has_clickprint, $auto_excluded_lines, $markers ) =
      @_;

    my $line_info = {};

    $line_info->{ line_number } = $line_number;

    # if (   $markers->{ comment }
    #     && $markers->{ comment }->[ 0 ]
    #     && ( $markers->{ comment }->[ 0 ] == $line_number ) )
    # {
    #     shift( @{ $markers->{ comment } } );
    #     $line_info->{ has_comment } = 1;
    # }
    # else
    # {
    #     $line_info->{ has_comment } = 0;
    # }

    my $line_text = html_strip( $line );

    $line_info->{ html_stripped_text_length } = length( $line_text );

    # if ( $auto_excluded_lines->[ $line_number ]->[ 0 ] )
    # {
    #     my $auto_exclude_explanation = $auto_excluded_lines->[ $line_number ]->[ 1 ];

    #     $line_info->{ auto_excluded }            = 1;
    #     $line_info->{ auto_exclude_explanation } = $auto_exclude_explanation;

    #     return $line_info;
    # }

    # $line_info->{ html_density } = MediaWords::Crawler::AnalyzeLines::get_html_density( $line );

    # $line_text =~ s/^\s*//;
    # $line_text =~ s/\s*$//;
    # $line_text =~ s/\s+/ /;

    $line_info->{ auto_excluded } = 0;

    # my ( $line_length, $line_starts_with_title_text ) =
    #   MediaWords::Crawler::AnalyzeLines::calculate_line_extraction_metrics_2( $line_text, $line, $title_text );

    # my ( $copyright_count ) = MediaWords::Crawler::AnalyzeLines::get_copyright_count( $line );

    my ( $article_has_clickprint, $article_has_sphereit_map, $description_similarity_discount, $sphereit_map_includes_line )
      = calculate_line_extraction_metrics( $line_number, $description, $line, $sphereit_map, $has_clickprint );

    # $line_info->{ line_length }                     = $line_length;
    # $line_info->{ line_starts_with_title_text }     = $line_starts_with_title_text;
    # $line_info->{ copyright_copy }                  = $copyright_count;
    # $line_info->{ article_has_clickprint }          = $article_has_clickprint;
    # $line_info->{ article_has_sphereit_map }        = $article_has_sphereit_map;
    # $line_info->{ description_similarity_discount } = $description_similarity_discount;
    # $line_info->{ sphereit_map_includes_line }      = $sphereit_map_includes_line;

    return $line_info;
}

sub calculate_line_extraction_metrics
{
    my $i              = shift;
    my $description    = shift;
    my $line           = shift;
    my $sphereit_map   = shift;
    my $has_clickprint = shift;

   # Readonly my $article_has_clickprint => $has_clickprint;    #<--- syntax error at (eval 980) line 11, near "Readonly my "

    # Readonly my $article_has_sphereit_map        => defined( $sphereit_map );
    # Readonly my $sphereit_map_includes_line      => ( defined( $sphereit_map ) && $sphereit_map->{ $i } );

    my ( $article_has_clickprint, $article_has_sphereit_map, $sphereit_map_includes_line );

    Readonly my $description_similarity_discount => get_description_similarity_discount( $line, $description );

    #my $description_similarity_discount = get_description_similarity_discount( $line, $description );

    my @ret =
      ( $article_has_clickprint, $article_has_sphereit_map, $description_similarity_discount, $sphereit_map_includes_line );

    return @ret;

    #    return ( $article_has_clickprint, $article_has_sphereit_map, $description_similarity_discount,
    #        $sphereit_map_includes_line );
}    #<--- syntax error at (eval 980) line 18, near ";

my $iterations = 0;

my $stripped_line = "foo";

my $stripped_description = "bar";

# while( 1)
# {
#     my $score = get_description_similarity_discount( "$stripped_line $iterations", "$stripped_description $iterations" );

#     $iterations++;

#     say STDERR "Iteration $iterations";

#     last if ( $iterations >= 1_000_000 );
# }

# say STDERR "calling perl_size";
# perl_size();
# exit;

{

    opendir XML_PREPROCESSED_RESULTS, $output_dir;

    my @xml_files = grep { /\.xml/ } readdir XML_PREPROCESSED_RESULTS;

    #@xml_files = qw ( 1046134.xml);

    foreach my $xml_file ( sort @xml_files )
    {
        my $parser = XML::LibXML->new();
        my $doc = $parser->parse_file( "$output_dir/$xml_file" ) or die;

        #$doc->setEncoding('UTF-8');

        my $root = $doc->getDocumentElement;

        my $download_content = get_value_of_base_64_node( $root, 'download_content_base64' );

        my $expected_preprocessed_text = get_value_of_base_64_node( $root, 'preprocessed_lines_base64' );

        my $actual_preprocessed_text_array = HTML::CruftText::clearCruftText( $download_content );

        my $actual_preprocessed_text = join( "", map { $_ . "\n" } @{ $actual_preprocessed_text_array } );

        #is( $actual_preprocessed_text, $expected_preprocessed_text, "preprocessed text $xml_file" );

        my $story_title       = get_value_of_base_64_node( $root, 'story_title' );
        my $story_description = get_value_of_base_64_node( $root, 'story_description' );

        my @lines = split( /[\n\r]+/, \$download_content );

        my $lines = MediaWords::Crawler::Extractor::preprocess( \@lines );

        my $title       = $story_title;
        my $description = $story_description;

        my $auto_excluded_lines = MediaWords::Crawler::Extractor::find_auto_excluded_lines( $lines );

        my $info_for_lines = [];

        #my $title_text = html_strip( $title );

        my $title_text = $title;
        $title_text =~ s/^\s*//;

        #$title_text =~ s/\s*$//;
        #$title_text =~ s/\s+/ /;

        my $markers        = MediaWords::Crawler::Extractor::find_markers( $lines );
        my $has_clickprint = HTML::CruftText::has_clickprint( $lines );
        my $sphereit_map   = MediaWords::Crawler::Extractor::get_sphereit_map( $markers );

        #MediaWords::Crawler::Extractor::print_time( "find_markers" );

        my $line = defined( $lines->[ 0 ] ) ? $lines->[ 0 ] : '';

        while ( 1 )
        {

            #MediaWords::DBI::Downloads::extract_preprocessed_lines_for_story( $lines, $title, $description );

        #MediaWords::DBI::Downloads::_do_extraction_from_content_ref( \$download_content, $story_title, $story_description );

            #my_extract_preprocessed_lines_for_story( $lines, $title, $description );

            #MediaWords::Crawler::AnalyzeLines::get_info_for_lines( $lines, $title, $description );
            #_heuristically_scored_lines_impl( $lines, $title, $description );

            #get_info_for_lines( $lines, $title, $description );

            my $line_info = calculate_full_line_metrics( $line, 0, $title_text, $description, $sphereit_map, $has_clickprint,
                $auto_excluded_lines, $markers );

#while ( 1 )
#{
#	get_info_for_lines_inner_loop ( $info_for_lines, $lines, $title_text, $description, $sphereit_map, $has_clickprint,  $auto_excluded_lines, $markers  );

            #}

            #my $info_for_lines = get_info_for_lines( $lines, $title, $description );
            #MediaWords::Crawler::Extractor::find_auto_excluded_lines( $lines );
            #_do_extraction_from_content_ref( \$download_content, $story_title, $story_description );

            $iterations++;

            say STDERR "Iteration $iterations";

            last if ( $iterations >= 10_000_000 );
        }

        last;

        # my $extract_results =
        #   MediaWords::DBI::Downloads::extract_preprocessed_lines_for_story( $actual_preprocessed_text_array,
        #     $story_title, $story_description );

        #$DB::single = 2;
        # MediaWords::DBI::DownloadTexts::update_extractor_results_with_text_and_html( $extract_results );

        # #say Dumper( $extract_results );

        # #exit;

        # my $expected_extracted_html = get_value_of_base_64_node( $root, 'extracted_html_base64' );

        # my $expected_extracted_html_ignore_sentence_splitting = $expected_extracted_html;

        # $expected_extracted_html_ignore_sentence_splitting =~ s/\n\n//g;

        # my $extracted_html_ignore_sentence_splitting = $extract_results->{ extracted_html };
        # $extracted_html_ignore_sentence_splitting =~ s/\n\n//g;

        # is(
        #     $extracted_html_ignore_sentence_splitting,
        #     $expected_extracted_html_ignore_sentence_splitting,
        #     "extracted html $xml_file"
        # );

        # my $expected_extracted_text = get_value_of_base_64_node( $root, 'extracted_text_base64' );

        # my $expected_extract_text_spaces_compressed = $expected_extracted_text;
        # $expected_extract_text_spaces_compressed =~ s/\s+//g;

        # my $actual_extract_text_spaces_compressed = $extract_results->{ extracted_text };
        # $actual_extract_text_spaces_compressed =~ s/\s+//g;

        # is( $actual_extract_text_spaces_compressed, $expected_extract_text_spaces_compressed, "extracted text $xml_file" );

        # my $story_line_numbers_expected = get_value_of_node( $root, 'story_line_numbers' );

        # my $story_line_numbers_actual = join ",",
        #   map { $_->{ line_number } } grep { $_->{ is_story } } @{ $extract_results->{ scores } };

        # is( $story_line_numbers_actual, $story_line_numbers_expected, "story line numbers" );
    }

    $iterations++;

    say STDERR "Iteration $iterations";

    last if ( $iterations >= 100 );
}

say STDERR "calling perl_size";
perl_size();
exit;

#Test::NoWarnings::had_no_warnings();

#done_testing;
