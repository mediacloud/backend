#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

#use Test::NoWarnings;
use Test::More skip_all => 'Not working yet';
use MediaWords::Crawler::Extractor qw (preprocess);
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use XML::LibXML;
use Encode;
use MIME::Base64;

Readonly my $output_dir => 'expected_preprocessed_results';

sub get_preprocessed_lines_from_downloads_id
{
    my ( $downloads_id ) = @_;
    my $dbs = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );
    my $download = $dbs->query( "SELECT * from downloads where downloads_id = ?", $downloads_id )->hash;

    die unless $download;

    return MediaWords::DBI::Downloads::fetch_preprocessed_content_lines( $dbs, $download );
}

TODO:
{

    todo_skip "Not working yet", 10 if 1;

    opendir XML_PREPROCESSED_RESULTS, $output_dir;

    my @xml_files = grep { /\.xml/ } readdir XML_PREPROCESSED_RESULTS;

    #@xml_files = qw ( 1046134.xml);

    foreach my $xml_file ( sort @xml_files )
    {
        my $parser = XML::LibXML->new();
        my $doc = $parser->parse_file( "$output_dir/$xml_file" ) or die;

        #$doc->setEncoding('UTF-8');

        my $root = $doc->getDocumentElement;

        my $downloads_id = ( $root->getElementsByTagName( "downloads_id" ) )[ 0 ]->firstChild->nodeValue;
        my $expected_preprocessed_text =
          ( $root->getElementsByTagName( 'preprocessed_lines_base64_encoded' ) )[ 0 ]->firstChild->nodeValue;

        $expected_preprocessed_text = decode_base64( $expected_preprocessed_text );

        my $actual_preprecessed_text_array = get_preprocessed_lines_from_downloads_id( $downloads_id );

        my $actual_preprocessed_text = join( "", map { $_ . "\n" } @{ $actual_preprecessed_text_array } );

        #    $actual_preprocessed_text = encode('utf8', $actual_preprocessed_text);

        is( $actual_preprocessed_text, $expected_preprocessed_text, "download: $downloads_id" );
    }

}

done_testing;
