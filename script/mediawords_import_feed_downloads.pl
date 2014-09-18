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
use Data::Dumper;
use MediaWords::Crawler::Handler;

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

# extract, story, and tag downloaded text for a $process_num / $num_processes slice of downloads
sub import_downloads
{
    my ( $xml_file_name ) = @_;

    open my $fh, $xml_file_name || die "Error opening file:$xml_file_name $@";

    my $parser = XML::LibXML->new;

    my $doc = $parser->parse_fh( $fh );

    my $root = $doc->documentElement() || die;

    my $db = MediaWords::DB::connect_to_db;

    my $downloads_processed = 0;

    foreach my $child_node ( $root->childNodes() )
    {

        #say STDERR "child_node: " . $child_node->nodeName();
        my $download = { map { $_->nodeName() => $_->textContent() } $child_node->childNodes() };

        my $old_downloads_id = $download->{ downloads_id };
        delete( $download->{ downloads_id } );

        my $decoded_content = decode_base64( $download->{ encoded_download_content_base_64 } );
        delete( $download->{ encoded_download_content_base_64 } );

        #say STDERR Dumper( $download );

        foreach my $key ( sort keys %{ $download } )
        {
            if ( !$download->{ $key } )
            {

                if ( !defined( $download->{ $key } ) )
                {
                    delete( $download->{ $key } );
                    next;
                }

                #$DB::single = 2 if $download->{ download_time } eq '2010-08-25 05:12:48.617132';

                if ( $download->{ $key } eq '' )
                {

                    #say STDERR "Deleting '$key' ";
                    delete( $download->{ $key } );
                }
            }
        }

        #say STDERR Dumper( $download );

        next if ( '(redundant feed)' eq $decoded_content );    # The download contains no content so don't add it.

        my $db_download = $db->create( 'downloads', $download );

        eval {
            MediaWords::Crawler::FeedHandler::handle_feed_content( $db, $db_download, $decoded_content );
            $downloads_processed++;

            say STDERR "Processed $downloads_processed downloads";

            #say STDERR Dumper( $db_download );
        };

        if ( $@ )
        {
            warn $@;

            #say "'$decoded_content'";
            say $old_downloads_id;

            #exit;
        }
    }
}

# fork of $num_processes
sub main
{
    my $xml_file_name = shift( @ARGV );

    say "Processing file $xml_file_name";

    die "Must specify file name" unless $xml_file_name;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    import_downloads( $xml_file_name );
}

main();
