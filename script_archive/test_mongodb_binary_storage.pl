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
use MongoDB;
use boolean;

use Text::Lorem::More;

sub main
{
    my @ARGS = @ARGV;

    my $list_labels;

    #my $db = MediaWords::DB::connect_to_db();

    my $conn = MongoDB::Connection->new;
    my $db   = $conn->file_write_test;

    my $downloaded_content = $db->downloaded_content;

    $downloaded_content->ensure_index( { "downloads_id" => 1 }, { unique => true } );

    my $lorem = Text::Lorem::More->new;

    srand( 12345 );

    # foreach my $iteration ( 0 .. 100_000_000 )
    # {
    # 	my $text = $lorem->paragraphs ( 10 );
    # 	# $db->query( "DELETE FROM downloaded_content where downloads_id = ? ", $iteration );
    # 	# $db->query( "INSERT INTO downloaded_content ( downloads_id, content) VALUES ( ?,  ? ) ", $iteration, $text );

    # 	$downloaded_content->remove ( { "downloads_id" => $iteration } );
    # 	$downloaded_content->insert ( { "downloads_id" => $iteration, "content" => $text } );

    # 	say $iteration . " text length " . length( $text ) . ' ' if $iteration % 1000 == 0;
    # }

    srand( 12345 );

    foreach my $iteration ( 0 .. 100_000_000 )
    {
        my $expected_text = $lorem->paragraphs( 10 );

        my $object = $downloaded_content->find_one( { "downloads_id" => $iteration } );

        #$downloaded_content->remove ( { "downloads_id" => $iteration } );
        #$downloaded_content->insert ( { "downloads_id" => $iteration, "content" => $text } );

        die "Text mismatch" unless $expected_text eq $object->{ content };

        say $iteration . " text length " . length( $expected_text ) . ' ' if $iteration % 1000 == 0;
    }

}

main();
