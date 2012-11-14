package MediaWords::GridFS;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# various helper functions for downloads

use strict;

use Encode;
use File::Path;
use HTTP::Request;
use IO::Uncompress::Gunzip;
use IO::Compress::Gzip;
use LWP::UserAgent;

use Archive::Tar::Indexed;
use MediaWords::Crawler::Extractor;
use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::DBI::DownloadTexts;
use MediaWords::StoryVectors;
use Carp;
use MongoDB;
use MongoDB::GridFS;

use Data::Dumper;

my $_gridfs;

sub gridfs_connection_settings
{
    my $mongo_settings = MediaWords::Util::Config::get_config->{ mongodb_gridfs };

    die unless defined( $mongo_settings );

    $mongo_settings = $mongo_settings->[ 0 ];

    say Dumper ( $mongo_settings );

    return $mongo_settings;
}

sub get_gridfs
{

    if ( not defined ( $_gridfs ) )
    {

	my $mongo_settings = gridfs_connection_settings();
	my $host = $mongo_settings->{ host };
	my $port = $mongo_settings->{ port };

	my $database_name = $mongo_settings->{ database };

	die unless defined( $host) and defined( $port ) and defined( $database_name );

	my $conn = MongoDB::Connection->new ( host => $host, port => $port );

	my $mongo_db   = $conn->get_database( $database_name);

	#my $mongo_db   = $conn->"$database";
	$_gridfs = $mongo_db->get_gridfs;

	die unless defined ( $_gridfs );
    }
	
    return $_gridfs;
}

sub store_download_content_ref
{
    my ( $gridfs, $content_ref, $downloads_id ) = @_;
 
    my $encoded_content = Encode::encode( 'utf-8', $$content_ref );

    my $gzipped_content;

    if ( !( IO::Compress::Gzip::gzip \$encoded_content => \$gzipped_content ) )
    {
    	die "Error gzipping content for $downloads_id: $IO::Compress::Gzip::GzipError" ;
    }

    my $basic_fh;
    open($basic_fh, '<', \$gzipped_content);
    my $gridfs_id = $gridfs->put( $basic_fh, { "filename" => $downloads_id } );

    return "$gridfs_id";
}

sub get_download_content_ref
{
    my ( $gridfs, $gridfs_id_str ) = @_;
 
    my $id =  MongoDB::OID->new(value => $gridfs_id_str );

    my $file = $gridfs->get( $id );

    if ( ! defined ( $file ) )
    {
	say STDERR Dumper ( $gridfs->all );
    }

    die "could not get file from gridfs for '$gridfs_id_str' " unless defined $file;

    my $gzipped_content = $file->slurp;

    my $content;

    if ( !( IO::Uncompress::Gunzip::gunzip \$gzipped_content => \$content ) )
    {
        die( "Error gunzipping content for $gridfs_id_str: $IO::Uncompress::Gunzip::GunzipError" );
    }

    my $decoded_content = decode( 'utf-8', $content );

    return \$decoded_content;   
}



1;
