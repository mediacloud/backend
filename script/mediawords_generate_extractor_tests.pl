#!/usr/bin/env perl

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
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use MediaWords::DBI::DownloadTexts;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use XML::LibXML;
use Data::Dumper;

use Digest::SHA qw(sha1 sha1_hex sha1_base64);

#use XML::LibXML::CDATASection;
use Encode;
use MIME::Base64;

#use XML::LibXML::Enhanced;

my $_re_generate_cache = 0;

Readonly my $output_dir => 'download_content_test_data';

sub create_base64_encoded_element
{
    my ( $name, $content ) = @_;

    my $ret = XML::LibXML::Element->new( $name );

    my $data_section = XML::LibXML::CDATASection->new( encode_base64( encode( "utf8", $content ) ) );

    $ret->appendChild( $data_section );

    return $ret;
}

sub store_preprocessed_result
{
    my ( $download, $preprocessed_lines, $extract_results, $content_ref, $story ) = @_;

    say STDERR "starting store_preprocessed_result";

    my $doc  = XML::LibXML::Document->new();
    my $root = $doc->createElement( 'download_test_results' );
    $doc->setEncoding( 'UTF-8' );
    $doc->setDocumentElement( $root );
    my $download_element = create_download_element( $download );

    $root->appendChild( $download_element );

    my $story_element = XML::LibXML::Element->new( 'story' );

    my $story_guid_element = XML::LibXML::Element->new( 'story_guid' );
    my $story_guid         = XML::LibXML::CDATASection->new( $story->{ guid } );
    $story_guid_element->appendChild( $story_guid );
    $story_element->appendChild( $story_guid_element );

    my $story_text = create_base64_encoded_element( 'story_title', $story->{ title } );
    $story_element->appendChild( $story_text );

    my $story_description = create_base64_encoded_element( 'story_description', $story->{ description } );
    $story_element->appendChild( $story_description );

    $root->appendChild( $story_element );

    my $lines_concated = join "", map { $_ . "\n" } @{ $preprocessed_lines };
    my $preprocessed_lines_element = create_base64_encoded_element( 'preprocessed_lines_base64', $lines_concated );

    $root->appendChild( $preprocessed_lines_element );

    my $content_element = create_base64_encoded_element( 'download_content_base64', ${ $content_ref } );

    $root->appendChild( $content_element );

    my $extractor_results = XML::LibXML::Element->new( 'extractor_results' );

    my $extracted_html = create_base64_encoded_element( 'extracted_html_base64', $extract_results->{ extracted_html } );
    $extractor_results->appendChild( $extracted_html );

    my $extracted_text = create_base64_encoded_element( 'extracted_text_base64', $extract_results->{ extracted_text } );
    $extractor_results->appendChild( $extracted_text );

    my $download_lines = create_base64_encoded_element( 'download_lines_base64', $extract_results->{ download_lines } );
    $extractor_results->appendChild( $extracted_text );

    my $story_line_numbers        = XML::LibXML::Element->new( 'story_line_numbers' );
    my $story_line_numbers_string = join ",",
      map { $_->{ line_number } } grep { $_->{ is_story } } @{ $extract_results->{ scores } };
    my $data_section = XML::LibXML::CDATASection->new( $story_line_numbers_string );
    $story_line_numbers->appendChild( $data_section );
    $extractor_results->appendChild( $story_line_numbers );

    #download_lines and preprocessed lines are probably the same but include both for completeness
    my $download_lines_concated = join "", map { $_ . "\n" } @{ $extract_results->{ download_lines } };
    my $download_lines = create_base64_encoded_element( 'download_lines_base64', $download_lines_concated );
    $extractor_results->appendChild( $download_lines );

    $root->appendChild( $extractor_results );

    my $file_name_hash_inputs = $story->{ guid } . $$content_ref;

    my $file_name_base = encode_base64( sha1( $file_name_hash_inputs ) );

    $file_name_base =~ s/\s//g;
    $file_name_base =~ s/\//\-/g;

    my $file_name = "$output_dir/$file_name_base.xml";
    say "XML file: '$file_name'";

    die unless $doc->toFile( $file_name, 1 );

    # download_id
    #download data_fields_info
    #preprocessed lines
}

sub store_downloads
{

    my $downloads = shift;

    my @downloads = @{ $downloads };

    say STDERR "Starting store_downloads";

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $download_results = [];

    my $dbs = MediaWords::DB::connect_to_db;

    for my $download ( @downloads )
    {
        say "Processing download $download->{downloads_id}";

        my $preprocessed_lines = MediaWords::DBI::Downloads::fetch_preprocessed_content_lines( $dbs, $download );
        my $extract_results = MediaWords::DBI::Downloads::extract_download( $dbs, $download );

        my $content_ref = MediaWords::DBI::Downloads::fetch_content( $dbs, $download );

        my $story = $dbs->query( "select * from stories where stories_id = ?", $download->{ stories_id } )->hash;

        store_preprocessed_result( $download, $preprocessed_lines, $extract_results, $content_ref, $story );
    }

}

sub create_download_element
{
    my ( $download ) = @_;

    my $download_element = XML::LibXML::Element->new( 'download' );
    foreach my $key ( sort keys %{ $download } )
    {
        $download_element->appendTextChild( $key, $download->{ $key } );
    }

    return $download_element;
}

# do a test run of the text extractor
sub main
{

    my $dbs = MediaWords::DB::connect_to_db;

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'                  => \$file,
        'downloads|d=s'             => \@download_ids,
        'regenerate_database_cache' => \$_re_generate_cache,
    ) or die;

    unless ( $file || ( @download_ids ) )
    {
        die "no options given ";
    }

    my $downloads;

    say STDERR @download_ids;

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
        die "must specify file or downloads id";

        $downloads = $dbs->query(
"SELECT * from downloads where downloads_id in (select distinct downloads_id from extractor_training_lines order by downloads_id)"
        )->hashes;
    }

    say STDERR Dumper( $downloads );

    die 'no downloads found ' unless scalar( @$downloads );

    say STDERR scalar( @$downloads ) . ' downloads';
    store_downloads( $downloads );
}

main();
