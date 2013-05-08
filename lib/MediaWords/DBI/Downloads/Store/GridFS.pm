package MediaWords::DBI::Downloads::Store::GridFS;

# class for storing / loading downloads in GridFS (MongoDB)

use strict;
use warnings;

use Moose;
with 'MediaWords::DBI::Downloads::Store';

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MongoDB 0.700.0;
use MongoDB::GridFS;

# MongoDB's query timeout, in ms
# (default timeout is 30 s, but MongoDB sometimes creates a new 2 GB data file for ~38 seconds,
#  so we set it to 60 s)
use constant MONGODB_QUERY_TIMEOUT => 60 * 1000;

# MongoDB's number of read / write retries
# (in case waiting 60 seconds for the read / write to happen doesn't help, the instance should
#  retry writing a couple of times)
use constant MONGODB_READ_RETRIES  => 3;
use constant MONGODB_WRITE_RETRIES => 3;

# MongoDB client, GridFS instance (lazy-initialized to prevent multiple forks using the same object)
my $_mongodb_client   = undef;
my $_mongodb_database = undef;
my $_mongodb_gridfs   = undef;

# Process PID (to prevent forks attempting to clone the MongoDB accessor objects)
my $_pid = 0;

# True if the package should connect to the MongoDB GridFS database used for testing
my $_use_testing_database = 0;

# Constructor
sub BUILD
{
    my ( $self, $args ) = @_;

    # Get settings
    if ( $args->{ use_testing_database } )
    {
        $_use_testing_database = 1;
    }
    else
    {
        $_use_testing_database = 0;
    }
}

# Destructor
sub DEMOLISH
{

    # Setting instances to undef should take care of the disconnect / cleanup automatically
    $_mongodb_gridfs   = undef;
    $_mongodb_database = undef;
    $_mongodb_client   = undef;
    $_pid              = 0;
}

sub _connect_to_mongodb_or_die
{
    my ( $self ) = @_;

    if ( $_pid == $$ and ( $_mongodb_client and $_mongodb_database and $_mongodb_gridfs ) )
    {

        # Already connected on the very same process
        return;
    }

    # Get settings
    my $mongo_settings;
    if ( $_use_testing_database )
    {
        $mongo_settings = MediaWords::Util::Config::get_config->{ mongodb_gridfs }->{ test };
        unless ( defined( $mongo_settings ) )
        {
            die "GridFS: Testing MongoDB database is not configured.\n";
        }
        say STDERR "GridFS: Will use testing MongoDB database.";
    }
    else
    {
        $mongo_settings = MediaWords::Util::Config::get_config->{ mongodb_gridfs }->{ mediawords };
    }

    unless ( defined( $mongo_settings ) )
    {
        die "GridFS: MongoDB connection settings in mediawords.yml are not configured properly.\n";
    }

    # Check settings
    my $host          = $mongo_settings->{ host };
    my $port          = $mongo_settings->{ port };
    my $database_name = $mongo_settings->{ database };

    unless ( defined( $host ) and defined( $port ) and defined( $database_name ) )
    {
        die "GridFS: MongoDB connection settings in mediawords.yml are not configured properly.\n";
    }

    # Connect
    $_mongodb_client = MongoDB::MongoClient->new( host => $host, port => $port, query_timeout => MONGODB_QUERY_TIMEOUT );
    unless ( $_mongodb_client )
    {
        die "GridFS: Unable to connect to MongoDB.\n";
    }

    $_mongodb_database = $_mongodb_client->get_database( $database_name );
    unless ( $_mongodb_database )
    {
        die "GridFS: Unable to choose a MongoDB database.\n";
    }

    $_mongodb_gridfs = $_mongodb_database->get_gridfs;
    unless ( $_mongodb_gridfs )
    {
        die "GridFS: Unable to connect use the MongoDB database as GridFS.\n";
    }

    # Save PID
    $_pid = $$;

    say STDERR "GridFS: Connected to GridFS download storage at '$host:$port/$database_name' for PID $$.";
}

# Returns true if a download already exists in a database
sub content_exists($$)
{
    my ( $self, $download ) = @_;

    _connect_to_mongodb_or_die();

    my $filename = '' . $download->{ downloads_id };
    my $file = $_mongodb_gridfs->find_one( { "filename" => $filename } );

    return ( defined $file );
}

# Removes content
sub remove_content($$)
{
    my ( $self, $download ) = @_;

    _connect_to_mongodb_or_die();

    my $filename = '' . $download->{ downloads_id };

    # Remove file(s) if already exist(s) -- MongoDB might store several versions of the same file
    while ( my $file = $_mongodb_gridfs->find_one( { "filename" => $filename } ) )
    {
        say STDERR "GridFS: Removing existing file '$filename'.";

        # "safe -- If true, each remove will be checked for success and die on failure."
        $_mongodb_gridfs->remove( { "filename" => $filename }, { safe => 1 } );
    }
}

# Moose method
sub store_content($$$$;$)
{
    my ( $self, $db, $download, $content_ref, $skip_encode_and_gzip ) = @_;

    _connect_to_mongodb_or_die();

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
            while ( my $file = $_mongodb_gridfs->find_one( { "filename" => $filename } ) )
            {
                say STDERR "GridFS: Removing existing file '$filename'.";
                $self->remove_content( $download );
            }

            # Write
            my $basic_fh;
            open( $basic_fh, '<', \$content_to_store );
            $gridfs_id = $_mongodb_gridfs->put( $basic_fh, { "filename" => $filename } );
            unless ( $gridfs_id )
            {
                die "GridFS: MongoDBs OID is empty.";
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
        die "GridFS: Unable to store download '$filename' to GridFS after " . MONGODB_WRITE_RETRIES . " retries.\n";
    }

    return $gridfs_id;
}

# Moose method
sub fetch_content($$;$)
{
    my ( $self, $download, $skip_gunzip_and_decode ) = @_;

    _connect_to_mongodb_or_die();

    unless ( $download->{ downloads_id } )
    {
        die "GridFS: Download ID is not defined.\n";
    }

    my $filename = '' . $download->{ downloads_id };

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
            $file = $_mongodb_gridfs->find_one( { 'filename' => $filename } );
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
        die "GridFS: Unable to read download '$filename' from GridFS after " . MONGODB_READ_RETRIES . " retries.\n";
    }

    unless ( defined( $file ) )
    {
        die "GridFS: Could not get file from GridFS for filename " . $filename . "\n";
    }

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
