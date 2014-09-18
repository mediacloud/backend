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
use MongoDB::GridFS;

use Text::Lorem::More;

sub main
{
    my @ARGS = @ARGV;

    my $list_labels;

    #my $db = MediaWords::DB::connect_to_db();

    my $conn = MongoDB::Connection->new;
    my $db   = $conn->grid_fs_file_write_test;

    my $grid = $db->get_gridfs;

    my $lorem = Text::Lorem::More->new;

    srand( 12345 );

    my $iterations = 10;

    say STDERR "starting add";

    my $ids = [];

    foreach my $iteration ( 0 .. $iterations )
    {

        say STDERR "adding";
        my $text = $lorem->paragraphs( 10 );

        # $db->query( "DELETE FROM downloaded_content where downloads_id = ? ", $iteration );
        # $db->query( "INSERT INTO downloaded_content ( downloads_id, content) VALUES ( ?,  ? ) ", $iteration, $text );

        my $basic_fh;
        open( $basic_fh, '<', \$text );

        my $id = $grid->put( $basic_fh, { "filename" => $iteration } );

        say "Grid_id: '$id'";

        push $ids, $id;
        say STDERR $iteration . " text length " . length( $text ) . ' ';    # if $iteration % 1000 == 0;
    }

    srand( 12345 );

    #say STDERR Dumper( $grid->all );

    say STDERR "starting retrieving";

    foreach my $iteration ( 0 .. $iterations )
    {
        say STDERR "retrieving $iteration";
        my $expected_text = $lorem->paragraphs( 10 );

        #my $file = $grid->find_one( { 'filename' => $iteration } );

        my $id   = $ids->[ $iteration ];
        my $file = $grid->get( $id );
        die "failed to get file for $iteration" unless defined( $file );

        die "Text mismatch" unless $expected_text eq $file->slurp;

        say $iteration . " text length " . length( $expected_text ) . ' ';    # if $iteration % 1000 == 0;
    }

}

main();
