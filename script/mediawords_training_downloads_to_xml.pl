#!/usr/bin/env perl

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use DBIx::Simple::MediaWords;
use XML::LibXML;
use Getopt::Long;
use Readonly;
use Carp;
use MIME::Base64;

sub main
{

    my $output_file;

    my Readonly $usage = 'USAGE: ./mediawords_training_downloads_to_xml.pl --file=FILE_NAME ';

    GetOptions( 'file=s' => \$output_file ) or die "$usage\n";

    die "$usage\n"
      unless $output_file;

    print STDERR "starting --  " . localtime() . "\n";

    my $db = MediaWords::DB::connect_to_db()
      || die DBIx::Simple::MediaWords->error;

    print STDERR "starting -- search query " . localtime() . "\n";

    my $doc  = XML::LibXML::Document->new();
    my $root = $doc->createElement( 'trained_downloads' );

    $doc->setDocumentElement( $root );

    my $downloads_rs = $db->query(
        "select distinct(downloads.*) from downloads natural join extractor_training_lines order by downloads_id" );

    while ( my $download = $downloads_rs->hash() )
    {

        my $download_element = $doc->createElement( 'download' );

        my $download_content = MediaWords::DBI::Downloads::fetch_content( $db, $download );

        $download_element->setAttribute( 'downloads_id', $download->{ downloads_id } );
        my $data_section = XML::LibXML::CDATASection->new( encode_base64( $$download_content ) );
        $download_element->appendChild( $data_section );
        $root->appendChild( $download_element );
    }

    print $doc->toFile( $output_file, 1 );

    print STDERR "finished --  " . localtime() . "\n";
}

main();
