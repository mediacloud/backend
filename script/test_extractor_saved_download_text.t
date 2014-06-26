#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use warnings;

my $cwd;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    $cwd = "$FindBin::Bin";
}

use Readonly;

## TODO update the expected results for the new extractor

use Test::More skip_all => 'TODO rewrite for the new extractor';
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

        is( $actual_preprocessed_text, $expected_preprocessed_text, "preprocessed text $xml_file" );

        my $story_title       = get_value_of_base_64_node( $root, 'story_title' );
        my $story_description = get_value_of_base_64_node( $root, 'story_description' );

        MediaWords::DBI::Downloads::_do_extraction_from_content_ref( \$download_content, $story_title, $story_description );

        my $extract_results =
          MediaWords::DBI::Downloads::extract_preprocessed_lines_for_story( $actual_preprocessed_text_array,
            $story_title, $story_description );

        #$DB::single = 2;
        MediaWords::DBI::DownloadTexts::update_extractor_results_with_text_and_html( $extract_results );

        #say Dumper( $extract_results );

        #exit;

        my $expected_extracted_html = get_value_of_base_64_node( $root, 'extracted_html_base64' );

        my $expected_extracted_html_ignore_sentence_splitting = $expected_extracted_html;

        $expected_extracted_html_ignore_sentence_splitting =~ s/\n\n//g;

        my $extracted_html_ignore_sentence_splitting = $extract_results->{ extracted_html };
        $extracted_html_ignore_sentence_splitting =~ s/\n\n//g;

        is(
            $extracted_html_ignore_sentence_splitting,
            $expected_extracted_html_ignore_sentence_splitting,
            "extracted html $xml_file"
        );

        my $expected_extracted_text = get_value_of_base_64_node( $root, 'extracted_text_base64' );

        my $expected_extract_text_spaces_compressed = $expected_extracted_text;
        $expected_extract_text_spaces_compressed =~ s/\s+//g;

        my $actual_extract_text_spaces_compressed = $extract_results->{ extracted_text };
        $actual_extract_text_spaces_compressed =~ s/\s+//g;

        is( $actual_extract_text_spaces_compressed, $expected_extract_text_spaces_compressed, "extracted text $xml_file" );

        my $story_line_numbers_expected = get_value_of_node( $root, 'story_line_numbers' );

        my $story_line_numbers_actual = join ",",
          map { $_->{ line_number } } grep { $_->{ is_story } } @{ $extract_results->{ scores } };

        is( $story_line_numbers_actual, $story_line_numbers_expected, "story line numbers" );

        last;
    }
}

Test::NoWarnings::had_no_warnings();

done_testing;
