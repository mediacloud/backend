#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::MC_Fork;

sub verify_downloads_files
{
    my $db = MediaWords::DB::connect_to_db;

    my $config = MediaWords::Util::Config::get_config;
    my $data_dir = $config->{ mediawords }->{ data_content_dir } || $config->{ mediawords }->{ data_dir };

    while ( 1 )
    {

        my $num_downloads = 0;

        my $relative_file_paths = $db->query(
	    " select distinct( relative_file_path) from downloads where " . 
	    " file_status = 'tbd'::download_file_status AND relative_file_path <> 'tbd'::text AND relative_file_path <> 'error'::text limit 1;"
        );

        while ( my $relative_file_path_hash = $relative_file_paths->hash() )
        {

            my $relative_file_path = $relative_file_path_hash->{ relative_file_path };
            say "Checking relative file path: $relative_file_path";

            my $file_path = "$data_dir/content/$relative_file_path";

            if ( -f $file_path )
            {
                say "$file_path exists";
                #$db->query( "UPDATE downloads set file_status = 'present' where relative_file_path = ? ",
                #    $relative_file_path );
            }
            else
            {
                say "$file_path doesn't exist";
                #$db->query( "UPDATE downloads set file_status = 'missing' where relative_file_path = ? ",
                #    $relative_file_path );
            }
        }

        return;
    }
}

sub main
{

    verify_downloads_files();
}

main();
