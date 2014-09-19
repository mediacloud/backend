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

use Text::Lorem::More;

sub main
{
    my @ARGS = @ARGV;

    my $list_labels;

    my $db = MediaWords::DB::connect_to_db();

    my $lorem = Text::Lorem::More->new;

    srand( 12345 );

    # foreach my $iteration ( 0 .. 1000 )
    # {
    # 	my $text = $lorem->paragraphs ( 10 );
    # 	$db->query( "DELETE FROM downloaded_content where downloads_id = ? ", $iteration );
    # 	$db->query( "INSERT INTO downloaded_content ( downloads_id, content) VALUES ( ?,  ? ) ", $iteration, $text );

    # 	say $iteration . "text length " . length( $text ) if $iteration % 1000 == 0;
    # }

    # exit;

    srand( 12345 );

    foreach my $iteration ( 0 .. 1_000 )
    {
        my $expected_text = $lorem->paragraphs( 10 );

        my $object = $db->query( " SELECT * from downloaded_content where downloads_id = ? LIMIT 1 ", $iteration )->hash();

        #$downloaded_content->remove ( { "downloads_id" => $iteration } );
        #$downloaded_content->insert ( { "downloads_id" => $iteration, "content" => $text } );

        #say Dumper ( $object );
        die "Text mismatch:\nGot:\n$expected_text\nExpected:\n$object->{content}"
          unless $expected_text eq $object->{ content };

        say $iteration . " text length " . length( $expected_text ) . ' ' if $iteration % 1000 == 0;
    }

}

main();
