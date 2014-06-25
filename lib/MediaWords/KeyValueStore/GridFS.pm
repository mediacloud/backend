package MediaWords::KeyValueStore::GridFS;

# class for storing / loading objects (raw downloads, CoreNLP annotator results, ...) to / from Mongo GridFS

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MongoDB 0.704.1.0;
use MongoDB::GridFS;
use Carp;

# MongoDB's query timeout, in ms
# (default timeout is 30 s, but MongoDB sometimes creates a new 2 GB data file for ~38 seconds,
#  so we set it to 60 s)
use constant MONGODB_QUERY_TIMEOUT => 60 * 1000;

# MongoDB's number of read / write retries
# (in case waiting 60 seconds for the read / write to happen doesn't help, the instance should
#  retry writing a couple of times)
use constant MONGODB_READ_RETRIES  => 10;
use constant MONGODB_WRITE_RETRIES => 10;

# MongoDB client, GridFS instance (lazy-initialized to prevent multiple forks using the same object)
has '_mongodb_client'   => ( is => 'rw' );
has '_mongodb_database' => ( is => 'rw' );
has '_mongodb_gridfs'   => ( is => 'rw' );

# Process PID (to prevent forks attempting to clone the MongoDB accessor objects)
has '_pid' => ( is => 'rw', default => 0 );

# Configuration
has '_conf_host'          => ( is => 'rw' );
has '_conf_port'          => ( is => 'rw' );
has '_conf_username'      => ( is => 'rw' );
has '_conf_password'      => ( is => 'rw' );
has '_conf_database_name' => ( is => 'rw' );

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    # Get arguments
    unless ( $args->{ database_name } )
    {
        confess "Please provide 'database_name' argument.\n";
    }
    my $gridfs_database_name = $args->{ database_name };

    # Get configuration
    my $config          = MediaWords::Util::Config::get_config;
    my $gridfs_host     = $config->{ mongodb_gridfs }->{ host } // 'localhost';
    my $gridfs_port     = $config->{ mongodb_gridfs }->{ port } // 27017;
    my $gridfs_username = $config->{ mongodb_gridfs }->{ username };
    my $gridfs_password = $config->{ mongodb_gridfs }->{ password };

    unless ( $gridfs_host and $gridfs_port )
    {
        confess "GridFS: MongoDB connection settings in mediawords.yml are not configured properly.\n";
    }

    # Store configuration
    $self->_conf_host( $gridfs_host );
    $self->_conf_port( $gridfs_port );
    $self->_conf_username( $gridfs_username );
    $self->_conf_password( $gridfs_password );
    $self->_conf_database_name( $gridfs_database_name );

    $self->_pid( $$ );
}

sub _connect_to_mongodb_or_die($)
{
    my ( $self ) = @_;

    if ( $self->_pid == $$ and ( $self->_mongodb_client and $self->_mongodb_database and $self->_mongodb_gridfs ) )
    {

        # Already connected on the very same process
        return;
    }

    # Get settings
    # Connect
    $self->_mongodb_client(
        MongoDB::MongoClient->new(
            host          => sprintf( 'mongodb://%s:%d', $self->_conf_host, $self->_conf_port ),
            username      => $self->_conf_username,
            password      => $self->_conf_password,
            query_timeout => MONGODB_QUERY_TIMEOUT
        )
    );
    unless ( $self->_mongodb_client )
    {
        confess "GridFS: Unable to connect to MongoDB.\n";
    }

    $self->_mongodb_database( $self->_mongodb_client->get_database( $self->_conf_database_name ) );
    unless ( $self->_mongodb_database )
    {
        confess "GridFS: Unable to choose a MongoDB database.\n";
    }

    $self->_mongodb_gridfs( $self->_mongodb_database->get_gridfs );
    unless ( $self->_mongodb_gridfs )
    {
        confess "GridFS: Unable to connect use the MongoDB database as GridFS.\n";
    }

    # Save PID
    $self->_pid( $$ );

    say STDERR "GridFS: Connected to GridFS storage at '" .
      $self->_conf_host . ":" . $self->_conf_port . "/" . $self->_conf_database_name . "' for PID $$.";
}

# Moose method
sub content_exists($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    $self->_connect_to_mongodb_or_die();

    my $filename = '' . $object_id;
    my $file = $self->_mongodb_gridfs->find_one( { "filename" => $filename } );

    return ( defined $file );
}

# Moose method
sub remove_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    $self->_connect_to_mongodb_or_die();

    my $filename = '' . $object_id;

    # Remove file(s) if already exist(s) -- MongoDB might store several versions of the same file
    while ( my $file = $self->_mongodb_gridfs->find_one( { "filename" => $filename } ) )
    {
        say STDERR "GridFS: Removing existing file '$filename'.";

        # "safe -- If true, each remove will be checked for success and die on failure."
        $self->_mongodb_gridfs->remove( { "filename" => $filename }, { safe => 1 } );
    }
}

# Moose method
sub store_content($$$$;$$)
{
    my ( $self, $db, $object_id, $content_ref, $skip_encode_and_compress, $use_bzip2_instead_of_gzip ) = @_;

    $self->_connect_to_mongodb_or_die();

    # Encode + gzip
    my $content_to_store;
    if ( $skip_encode_and_compress )
    {
        $content_to_store = $$content_ref;
    }
    else
    {
        $content_to_store = $self->encode_and_compress( $content_ref, $object_id, $use_bzip2_instead_of_gzip );
    }

    my $filename = '' . $object_id;
    my $gridfs_id;

    # MongoDB sometimes times out when writing because it's busy creating a new data file,
    # so we'll try to write several times
    for ( my $retry = 0 ; $retry < MONGODB_WRITE_RETRIES ; ++$retry )
    {
        if ( $retry > 0 )
        {
            say STDERR "GridFS: Retrying...";
        }

        eval {

            # Remove file(s) if already exist(s) -- MongoDB might store several versions of the same file
            while ( my $file = $self->_mongodb_gridfs->find_one( { "filename" => $filename } ) )
            {
                say STDERR "GridFS: Removing existing file '$filename'.";
                $self->remove_content( $db, $object_id );
            }

            # Write
            my $basic_fh;
            open( $basic_fh, '<', \$content_to_store );
            $gridfs_id = $self->_mongodb_gridfs->put( $basic_fh, { "filename" => $filename } );
            unless ( $gridfs_id )
            {
                confess "GridFS: MongoDBs OID is empty.";
            }

            $gridfs_id = "gridfs:$gridfs_id";
        };

        if ( $@ )
        {
            say STDERR "GridFS: Write to '$filename' didn't succeed because: $@";
        }
        else
        {
            last;
        }
    }

    unless ( $gridfs_id )
    {
        confess "GridFS: Unable to store object ID $object_id to GridFS after " . MONGODB_WRITE_RETRIES . " retries.\n";
    }

    return $gridfs_id;
}

# Moose method
sub fetch_content($$$;$$$)
{
    my ( $self, $db, $object_id, $object_path, $skip_uncompress_and_decode, $use_bunzip2_instead_of_gunzip ) = @_;

    $self->_connect_to_mongodb_or_die();

    unless ( defined $object_id )
    {
        confess "GridFS: Object ID is undefined.\n";
    }

    my $filename = '' . $object_id;

    my $id = MongoDB::OID->new( filename => $filename );

    # MongoDB sometimes times out when reading because it's busy creating a new data file,
    # so we'll try to read several times
    my $attempt_to_read_succeeded = 0;
    my $file                      = undef;
    for ( my $retry = 0 ; $retry < MONGODB_READ_RETRIES ; ++$retry )
    {
        if ( $retry > 0 )
        {
            say STDERR "GridFS: Retrying...";
        }

        eval {

            # Read
            my $gridfs_file = $self->_mongodb_gridfs->find_one( { 'filename' => $filename } );
            unless ( defined $gridfs_file )
            {
                confess "GridFS: unable to find file '$filename'.";
            }
            $file                      = $gridfs_file->slurp;
            $attempt_to_read_succeeded = 1;
        };

        if ( $@ )
        {
            say STDERR "GridFS: Read from '$filename' didn't succeed because: $@";
        }
        else
        {
            last;
        }
    }

    unless ( $attempt_to_read_succeeded )
    {
        confess "GridFS: Unable to read object ID $object_id from GridFS after " . MONGODB_READ_RETRIES . " retries.\n";
    }

    unless ( defined( $file ) )
    {
        confess "GridFS: Could not get file '$filename'.\n";
    }

    my $gzipped_content = $file;

    # Gunzip + decode
    my $decoded_content;
    if ( $skip_uncompress_and_decode )
    {
        $decoded_content = $gzipped_content;
    }
    else
    {
        $decoded_content = $self->uncompress_and_decode( \$gzipped_content, $object_id, $use_bunzip2_instead_of_gunzip );
    }

    return \$decoded_content;
}

no Moose;    # gets rid of scaffolding

1;
