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
use XML::LibXML;

#use XML::LibXML::CDATASection;
use Encode;
use MIME::Base64;

#use XML::LibXML::Enhanced;

my $_re_generate_cache = 0;

Readonly my $output_dir => 'expected_preprocessed_results';

sub store_preprocessed_result
{
    my ( $download, $preprocessed_lines ) = @_;

    my $doc  = XML::LibXML::Document->new();
    my $root = $doc->createElement('download_test_results');
    $doc->setEncoding('UTF-8');
    $doc->setDocumentElement($root);
    my $download_element = create_download_element($download);

    $root->appendChild($download_element);

    my $preprocessed_lines_element = XML::LibXML::Element->new('preprocessed_lines_base64_encoded');

    my $lines_concated = join "", map { $_ . "\n" } @{$preprocessed_lines};

    #$lines_concated = encode('utf8',$lines_concated  );

    my $data_section = XML::LibXML::CDATASection->new( encode_base64($lines_concated) );

    $preprocessed_lines_element->appendChild($data_section);

    $root->appendChild($preprocessed_lines_element);

    print "XML file:$output_dir/$download->{downloads_id}.xml\n";

    die unless $doc->toFile( "$output_dir/$download->{downloads_id}.xml", 1 );

    # download_id
    #download data_fields_info
    #preprocessed lines
}

sub stored_preprocessed_info
{

    my $downloads = shift;

    my @downloads = @{$downloads};

    @downloads = sort { $a->{downloads_id} <=> $b->{downloads_id} } @downloads;

    my $download_results = [];

    my $dbs = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);

    for my $download (@downloads)
    {
        my $preprocessed_lines = MediaWords::DBI::Downloads::fetch_preprocessed_content_lines($download);

        store_preprocessed_result( $download, $preprocessed_lines );
    }

}

sub create_download_element
{
    my ($download) = @_;

    my $download_element = XML::LibXML::Element->new('download');
    foreach my $key ( sort keys %{$download} )
    {
        $download_element->appendTextChild( $key, $download->{$key} );
    }

    return $download_element;
}

# do a test run of the text extractor
sub main
{

    my $db = MediaWords::DB->authenticate();

    my $dbs = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'                  => \$file,
        'downloads|d=s'             => \@download_ids,
        'regenerate_database_cache' => \$_re_generate_cache,
    ) or die;

    unless ($file || (@download_ids)) 
    {
         die "no options given ";
    }

    my $downloads;

    if (@download_ids)
    {
        $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    }
    elsif ($file)
    {
        open( DOWNLOAD_ID_FILE, $file ) || die("Could not open file: $file");
        @download_ids = <DOWNLOAD_ID_FILE>;
        $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    }
    else
    {
        $downloads =
          $dbs->query(
"SELECT * from downloads where downloads_id in (select distinct downloads_id from extractor_training_lines order by downloads_id)"
          )->hashes;
    }

    stored_preprocessed_info($downloads);
}

main();
