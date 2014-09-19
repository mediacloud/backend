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
use Store::CouchDB;

use Text::Lorem::More;

sub main
{
    my @ARGS = @ARGV;

    my $list_labels;

    #my $db = MediaWords::DB::connect_to_db();

    Readonly my $dbname => 'downloads';

    my $db = Store::CouchDB->new();

    $db->config( { host => 'localhost', db => 'downloads' } );

    my $lorem = Text::Lorem::More->new;

    srand( 12345 );

    # foreach my $iteration ( 0 .. 100_000 )
    # {
    # 	my $text = $lorem->paragraphs ( 10 );

    # 	$db->put_doc( { doc => { "downloads_id" => $iteration, "content" => $text }, dbname => $dbname  } );

    # 	say $iteration . " text length " . length( $text ) . ' ' if $iteration % 1000 == 0;
    # }

    srand( 12345 );

    foreach my $iteration ( 0 .. 100_000 )
    {
        my $expected_text = $lorem->paragraphs( 10 );

        next if $iteration == 0;

        my $couch = {
            view => 'application/content_by_downloads_id',
            opts => { key => $iteration }
        };

        my $status = $db->get_view( $couch );

        my %hash   = %{ $status };
        my $object = ( values $status )[ 0 ];

        my $content = $object->{ content };

        die "Text mismatch expected:\n'$expected_text'\ngot:\n'$content'\n" unless $expected_text eq $content;

        say $iteration . " text length " . length( $expected_text ) . ' ' if $iteration % 1000 == 0;
    }

}

main();
