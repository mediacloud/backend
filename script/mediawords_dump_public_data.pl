#!/usr/bin/perl

# create a dump with all public data.
# the output is a .tar.gz'd directory of csv files.
# requires a working directory as an argument, which is where to generate the csv files before tarring them

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use File::Path;
use FileHandle;
use IPC::System::Simple;

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::CommonLibs;


# tag sets to omit from dump
use constant OMIT_TAG_SETS => qw( workflow );

# dump the given table or query to the given file
sub dump_table
{
    my ( $db, $table, $file ) = @_;

    if ( $table =~ m/\s/ )
    {

        # if it's got a space, it's a query
        $table = "($table)";
    }
    elsif ( !$file )
    {

        # if it's not a query and there's no filename, use table.csv
        $file = "${table}.csv";
    }

    print "dumping $file ...\n";

    my $fh = FileHandle->new( ">$file" );
    if ( !$fh )
    {
        die( "Unable to open file $file" );
    }

    $db->dbh->do( "copy $table to STDOUT with csv header" );

    my $buf;
    while ( $db->dbh->pg_getcopydata( $buf ) >= 0 )
    {
        $fh->print( $buf );
    }

    $fh->close;
}

sub main
{
    my ( $dir, $tar_file ) = @ARGV;

    if ( !$dir || !$tar_file )
    {
        die( "usage: mediawords_dump_public_data.pl <working directory> <output tar file>" );
    }

    my $dump_dir = "$dir/mediacloud-dump";
    if ( !mkdir( $dump_dir ) )
    {
        die( "Unable to mkdir $dump_dir: $!" );
    }

    my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    if ( !chdir( $dump_dir ) )
    {
        die( "Unable to chdir $dump_dir: $!" );
    }

    my $omit_tag_sets = join( ',', map { $db->dbh->quote( $_ ) } ( OMIT_TAG_SETS ) );

    dump_table( $db, 'media' );
    dump_table( $db, 'feeds' );
    dump_table( $db, "select * from tag_sets where name not in ($omit_tag_sets)", 'tag_sets.csv' );
    dump_table( $db,
        "select t.* from tags t, tag_sets ts where t.tag_sets_id = ts.tag_sets_id and ts.name not in ($omit_tag_sets)",
        'tags.csv' );
    dump_table( $db, 'feeds_tags_map' );
    dump_table( $db, 'media_tags_map' );
    dump_table( $db, 'select stories_id, media_id, url, guid, title, publish_date, collect_date from stories',
        'stories.csv' );
    dump_table( $db, 'feeds_stories_map' );
    dump_table( $db, 'stories_tags_map' );

    if ( !chdir( $dir ) )
    {
        die( "Unable to chdir $dir: $!" );
    }

    IPC::System::Simple::system( "tar -cvzf $tar_file mediacloud-dump/" );

    File::Path::rmtree( $dump_dir );
}

main();
