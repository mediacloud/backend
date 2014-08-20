#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::Process;

use XML::LibXML;
use MIME::Base64;
use Encode;

sub xml_tree_from_hash
{
    my ( $hash, $name ) = @_;

    my $node = XML::LibXML::Element->new( $name );

    foreach my $key ( sort keys %{ $hash } )
    {

        #say STDERR "appending '$key'  $hash->{ $key } ";
        $node->appendTextChild( $key, $hash->{ $key } );
    }

    return $node;
}

sub export_downloads
{
    my ( $start_downloads_id, $end_downloads_id ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    my $doc  = XML::LibXML::Document->new();
    my $root = $doc->createElement( 'downloads' );

    $doc->setDocumentElement( $root );

    my $cur_downloads_id = $start_downloads_id;

    while ( $cur_downloads_id <= $end_downloads_id )
    {

        say STDERR "Downloads_id $cur_downloads_id (end: $end_downloads_id)";

        my $download =
          $db->query( " SELECT * from downloads where downloads_id >= ?  and type = 'feed' and state = 'success' limit 1 ",
            $cur_downloads_id )->hash();

        my $download_content = MediaWords::DBI::Downloads::fetch_content( $db, $download );

        my $download_content_base64 = encode_base64( encode( "utf8", $$download_content ) );

        if ( '(redundant feed)' ne $download_content_base64 )
        {

            $download->{ encoded_download_content_base_64 } = $download_content_base64;

            $root->appendChild( xml_tree_from_hash( $download, 'download' ) );
        }

        $cur_downloads_id = $download->{ downloads_id } + 1;
    }

    my $file = ">/tmp/downloads.xml";
    open OUT, $file;
    print OUT $doc->toString;
}

# fork of $num_processes
sub main
{

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    export_downloads( 1, 100 );
}

main();
