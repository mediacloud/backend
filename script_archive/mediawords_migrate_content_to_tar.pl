#!/usr/bin/perl

# move all existing downloads from the old individual file storage to the new indexed tar storage
#
# start with '-s' to start a fresh job deleting all downloads with non-tar-storage

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::DBI::Downloads;

use File::Find;

sub create_tar_downloads_queue
{
    my ( $db ) = @_;

    my ( $queue_table_exists ) = $db->query( "select * from pg_tables where tablename = 'tar_downloads_queue'" )->flat;
    if ( $queue_table_exists )
    {
        $db->query( "drop table tar_downloads_queue" );
    }
    
    $db->query( "create table tar_downloads_queue as select downloads_id from downloads where not path like 'tar:%'" );
    $db->query( "create index tar_downloads_queue_download on tar_downloads_queue (downloads_id)" );
}

# fetch the content using the old file fetching and store using the new tar system
sub migrate_download
{
    my ( $db, $download ) = @_;
    
    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $download );
    
    MediaWords::DBI::Downloads::store_content( $db, $download, $content_ref );
}

# undo a previous migration based on an existing set of content files
sub undo_migration
{
    my ( $db ) = @_;
    
    my $config = MediaWords::Util::Config::get_config;
    my $data_dir = $config->{ mediawords }->{ data_content_dir } || $config->{ mediawords }->{ data_dir };
    
    my $files = [];
    
    File::Find::find( sub { if ( /^\d+\.gz$/ ) { push( @{ $files }, $File::Find::name ) } }, "$data_dir/content" );

    for my $file ( @{ $files } )
    {
        if ( !( $file =~ m~content/(.*/(\d+)\.gz)$~ ) )
        {
            die( "Unable to parse file '$file'" );
        }
        my ( $download_path, $downloads_id ) = ( $1, $2 );
        
        $db->query( 
            "update downloads set path = ? where downloads_id = ?",
            $download_path, $downloads_id
            );
        print "$downloads_id -> $download_path\n";
    }
}

sub main 
{
    my ( $opt ) = @ARGV;
    
    my $db = MediaWords::DB::connect_to_db;
    
    if ( $opt eq '-r' )
    {
        undo_migration( $db );
        return;
    }
    
    if ( $opt eq '-s' )
    {
        create_tar_downloads_queue( $db );
    }
    
    my $i = 0;
    while ( 1 ) 
    {
        my $downloads = $db->query( 
            "select * from tar_downloads_queue t, downloads d " .
            "  where d.downloads_id = t.downloads_id limit 10"
            )->hashes;
        
        @{ $downloads } || last;

        for my $download ( @{ $downloads } )
        {
            migrate_download( $db, $download );
            $db->query( "delete from tar_downloads_queue where downloads_id = ?", $download->{ downloads_id } );
        }
        
        print( ( ++$i * 10 ) . " downloads migrated\n" );
    }
    
}

main();