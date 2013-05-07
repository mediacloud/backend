package MediaWords::DBI::Downloads::Store::GridFS;

# class for storing / loading downloads in GridFS (MongoDB)

use strict;
use warnings;

use Moose;
with 'MediaWords::DBI::Downloads::Store';

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MongoDB;
use MongoDB::GridFS;

my $_use_testing_database = 0;

# Constructor
sub BUILD
{
    my ( $self, $args ) = @_;

    if ( $args->{ use_testing_database } )
    {
        $_use_testing_database = 1;
    }
    else
    {
        $_use_testing_database = 0;
    }
}

# Return a MongoDB connection or die
sub _mongodb_connection
{

    # Get settings
    my $mongo_settings;
    if ( $_use_testing_database )
    {
        $mongo_settings = MediaWords::Util::Config::get_config->{ mongodb_gridfs }->{ test };
        unless ( defined( $mongo_settings ) )
        {
            die "Testing MongoDB database is not configured.";
        }
        say STDERR "Will use testing MongoDB database.";
    }
    else
    {
        $mongo_settings = MediaWords::Util::Config::get_config->{ mongodb_gridfs }->{ mediawords };
    }

    unless ( defined( $mongo_settings ) )
    {
        die "MongoDB database is not configured.\n";
    }

    $mongo_settings = $mongo_settings->[ 0 ];

    # Check settings
    my $host = $mongo_settings->{ host };
    my $port = $mongo_settings->{ port };

    my $database_name = $mongo_settings->{ database };

    unless ( defined( $host ) and defined( $port ) and defined( $database_name ) )
    {
        die "MongoDB database is not configured.\n";
    }

    # Connect
    my $conn = MongoDB::Connection->new( host => $host, port => $port );
    my $mongo_db = $conn->get_database( $database_name );

    return $mongo_db;
}

# Returns true if a download already exists in a database
sub content_exists($$)
{
    my ( $self, $download ) = @_;

    my $mongo_db = _mongodb_connection() or die "Unable to connect to MongoDB.\n";
    my $gridfs = $mongo_db->get_gridfs;

    my $filename = '' . $download->{ downloads_id };
    my $file = $gridfs->find_one( { "filename" => $filename } );

    return ( defined $file );
}

# Removes content
sub remove_content($$)
{
    my ( $self, $download ) = @_;

    my $mongo_db = _mongodb_connection() or die "Unable to connect to MongoDB.\n";
    my $gridfs = $mongo_db->get_gridfs;

    my $filename = '' . $download->{ downloads_id };

    # Remove file(s) if already exist(s) -- MongoDB might store several versions of the same file
    while ( my $file = $gridfs->find_one( { "filename" => $filename } ) )
    {
        say STDERR "Removing existing file '$filename'.";

        # "safe -- If true, each remove will be checked for success and die on failure."
        $gridfs->remove( { "filename" => $filename }, { safe => 1 } );
    }
}

# Moose method
sub store_content($$$$;$)
{
    my ( $self, $db, $download, $content_ref, $skip_encode_and_gzip ) = @_;

    my $mongo_db = _mongodb_connection() or die "Unable to connect to MongoDB.\n";
    my $gridfs = $mongo_db->get_gridfs;

    # Encode + gzip
    my $content_to_store;
    if ( $skip_encode_and_gzip )
    {
        $content_to_store = $$content_ref;
    }
    else
    {
        $content_to_store = $self->encode_and_gzip( $content_ref, $download->{ downloads_id } );
    }

    my $filename = '' . $download->{ downloads_id };
    my $gridfs_id;

    # MongoDB sometimes times out when writing, so we'll try to write several times
    my Readonly $mongodb_write_retries = 3;
    for ( my $retry = 0 ; $retry < $mongodb_write_retries ; ++$retry )
    {
        if ( $retry > 0 )
        {
            say STDERR "Retrying...";
        }

        eval {

            # Remove file(s) if already exist(s) -- MongoDB might store several versions of the same file
            while ( my $file = $gridfs->find_one( { "filename" => $filename } ) )
            {
                say STDERR "Removing existing file '$filename'.";
                $self->remove_content( $download );
            }

            # Write
            my $basic_fh;
            open( $basic_fh, '<', \$content_to_store );
            $gridfs_id = $gridfs->put( $basic_fh, { "filename" => $filename } );
            unless ( $gridfs_id )
            {
                die "MongoDBs OID is empty.";
            }

            $gridfs_id = "gridfs:$gridfs_id";
        };

        if ( $@ )
        {
            say STDERR "GridFS write to '$filename' didn't succeed because: $@";
        }
        else
        {
            last;
        }
    }

    unless ( $gridfs_id )
    {
        die "Unable to store download '$filename' to GridFS after $mongodb_write_retries retries.\n";
    }

    return $gridfs_id;
}

# Moose method
sub fetch_content($$;$)
{
    my ( $self, $download, $skip_gunzip_and_decode ) = @_;

    my $mongo_db = _mongodb_connection() or die "Unable to connect to MongoDB.\n";
    my $gridfs = $mongo_db->get_gridfs;

    unless ( $download->{ downloads_id } )
    {
        die "Download ID is not defined.\n";
    }

    my $filename = '' . $download->{ downloads_id };

    my $id = MongoDB::OID->new( filename => $filename );

    # Read
    my $file = $gridfs->find_one( { 'filename' => $filename } );

    die "could not get file from gridfs for filename " . $filename . "\n" unless defined $file;

    my $gzipped_content = $file->slurp;

    # Gunzip + decode
    my $decoded_content;
    if ( $skip_gunzip_and_decode )
    {
        $decoded_content = $gzipped_content;
    }
    else
    {
        $decoded_content = $self->gunzip_and_decode( \$gzipped_content, $download->{ downloads_id } );
    }

    return \$decoded_content;
}

no Moose;    # gets rid of scaffolding

1;
