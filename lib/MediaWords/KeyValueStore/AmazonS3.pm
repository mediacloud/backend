package MediaWords::KeyValueStore::AmazonS3;

# class for storing / loading objects (raw downloads, CoreNLP annotator results, ...) to / from Amazon S3

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::Util::Compress;
use Net::Amazon::S3;
use Net::Amazon::S3::Client;
use Net::Amazon::S3::Client::Bucket;
use POSIX qw(floor);
use Carp;
use Readonly;

# Should the Amazon S3 module use secure (SSL-encrypted) connections?
Readonly my $AMAZON_S3_USE_SSL => 0;

# How many seconds should the module wait before bailing on a request to S3 (in seconds)
# (Timeout should "fit in" at least $AMAZON_S3_READ_ATTEMPTS number of retries
# within the time period)
Readonly my $AMAZON_S3_TIMEOUT => 60;

# Check if content exists before storing (good for debugging, slows down the stores)
Readonly my $AMAZON_S3_CHECK_IF_EXISTS_BEFORE_STORING => 0;

# Check if content exists before fetching (good for debugging, slows down the fetches)
Readonly my $AMAZON_S3_CHECK_IF_EXISTS_BEFORE_FETCHING => 1;

# Check if content exists before deleting (good for debugging, slows down the deletes)
Readonly my $AMAZON_S3_CHECK_IF_EXISTS_BEFORE_DELETING => 1;

# S3's number of read / write attempts
# (in case waiting 20 seconds for the read / write to happen doesn't help, the instance should
# retry writing a couple of times)
Readonly my $AMAZON_S3_READ_ATTEMPTS  => 3;
Readonly my $AMAZON_S3_WRITE_ATTEMPTS => 3;

# Configuration
has '_conf_access_key_id'     => ( is => 'rw' );
has '_conf_secret_access_key' => ( is => 'rw' );
has '_conf_bucket_name'       => ( is => 'rw' );
has '_conf_directory_name'    => ( is => 'rw', default => '' );

# Net::Amazon::S3 instance, bucket (lazy-initialized to prevent multiple forks using the same object)
has '_s3'        => ( is => 'rw' );
has '_s3_client' => ( is => 'rw' );
has '_s3_bucket' => ( is => 'rw' );

# Process PID (to prevent forks attempting to clone the Net::Amazon::S3 accessor objects)
has '_pid' => ( is => 'rw', default => 0 );

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    # Get arguments
    unless ( $args->{ bucket_name } )
    {
        confess "Please provide 'bucket_name' argument.";
    }
    my $bucket_name = $args->{ bucket_name };
    my $directory_name = $args->{ directory_name } || '';

    # Validate constants
    if ( $AMAZON_S3_READ_ATTEMPTS < 1 )
    {
        confess "AMAZON_S3_READ_ATTEMPTS must be >= 1";
    }
    if ( $AMAZON_S3_WRITE_ATTEMPTS < 1 )
    {
        confess "AMAZON_S3_WRITE_ATTEMPTS must be >= 1";
    }

    # Get configuration
    my $config = MediaWords::Util::Config::get_config;

    unless ( defined( $config->{ amazon_s3 } ) )
    {
        confess "AmazonS3: Amazon S3 connection settings in mediawords.yml are not configured properly.";
    }

    my $access_key_id     = $config->{ amazon_s3 }->{ access_key_id };
    my $secret_access_key = $config->{ amazon_s3 }->{ secret_access_key };

    # Directory is optional
    unless ( $access_key_id and $secret_access_key and $bucket_name )
    {
        confess "AmazonS3: Amazon S3 connection settings in mediawords.yml are not configured properly.";
    }

    # Add slash to the end of the directory name (if it doesn't exist yet)
    if ( $directory_name and substr( $directory_name, -1, 1 ) ne '/' )
    {
        $directory_name .= '/';
    }

    # Store configuration
    $self->_conf_access_key_id( $access_key_id );
    $self->_conf_secret_access_key( $secret_access_key );
    $self->_conf_bucket_name( $bucket_name );
    $self->_conf_directory_name( $directory_name || '' );

    $self->_pid( $$ );
}

sub _initialize_s3_or_die($)
{
    my ( $self ) = @_;

    if ( $self->_pid == $$ and ( $self->_s3 and $self->_s3_bucket ) )
    {

        # Already initialized on the very same process
        return;
    }

    # Timeout should "fit in" at least $AMAZON_S3_READ_ATTEMPTS number of retries
    # within the time period
    my $request_timeout = floor( ( $AMAZON_S3_TIMEOUT / $AMAZON_S3_READ_ATTEMPTS ) - 1 );
    if ( $request_timeout < 10 )
    {
        confess "Amazon S3 request timeout ($request_timeout) too small.";
    }

    # Initialize
    $self->_s3(
        Net::Amazon::S3->new(
            aws_access_key_id     => $self->_conf_access_key_id,
            aws_secret_access_key => $self->_conf_secret_access_key,
            retry                 => 1,
            secure                => $AMAZON_S3_USE_SSL,
            timeout               => $request_timeout
        )
    );
    unless ( $self->_s3 )
    {
        confess "AmazonS3: Unable to initialize Net::Amazon::S3 instance.";
    }
    $self->_s3_client( Net::Amazon::S3::Client->new( s3 => $self->_s3 ) );

    # Get the bucket ($_s3->bucket would not verify that the bucket exists)
    my @buckets = $self->_s3_client->buckets;
    foreach my $bucket ( @buckets )
    {
        if ( $bucket->name eq $self->_conf_bucket_name )
        {
            $self->_s3_bucket( $bucket );
        }
    }
    unless ( $self->_s3_bucket )
    {
        confess "AmazonS3: Unable to get bucket '" . $self->_conf_bucket_name . "'.";
    }

    # Save PID
    $self->_pid( $$ );

    my $path = (
          $self->_conf_directory_name
        ? $self->_conf_bucket_name . '/' . $self->_conf_directory_name
        : $self->_conf_bucket_name
    );
    say STDERR "AmazonS3: Initialized Amazon S3 storage at '$path' for PID $$.";
}

sub _object_for_object_id($$)
{
    my ( $self, $object_id ) = @_;

    unless ( defined $object_id )
    {
        confess "Object ID is undefined.";
    }

    my $filename = $self->_conf_directory_name . $object_id;
    my $object = $self->_s3_bucket->object( key => $filename );

    return $object;
}

# Moose method
sub content_exists($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    $self->_initialize_s3_or_die();

    my $object = $self->_object_for_object_id( $object_id );
    if ( $object->exists )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Moose method
sub remove_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    $self->_initialize_s3_or_die();

    if ( $AMAZON_S3_CHECK_IF_EXISTS_BEFORE_DELETING )
    {
        unless ( $self->content_exists( $db, $object_id, $object_path ) )
        {
            confess "AmazonS3: object with ID " . $object_id . " does not exist.";
        }
    }

    my $object = $self->_object_for_object_id( $object_id );

    $object->delete;

    return 1;
}

# Moose method
sub store_content($$$$)
{
    my ( $self, $db, $object_id, $content_ref ) = @_;

    $self->_initialize_s3_or_die();

    if ( $AMAZON_S3_CHECK_IF_EXISTS_BEFORE_STORING )
    {
        if ( $self->content_exists( $db, $object_id ) )
        {
            say STDERR "AmazonS3: object ID $object_id already exists, " .
              "will store a new version or overwrite (depending on whether or not versioning is enabled).";
        }
    }

    # Encode + gzip
    my $content_to_store;
    eval { $content_to_store = MediaWords::Util::Compress::encode_and_gzip( $$content_ref ); };
    if ( $@ or ( !defined $content_to_store ) )
    {
        confess "Unable to compress object ID $object_id: $@";
    }

    my $write_was_successful = 0;
    my $object;

    # S3 sometimes times out when writing, so we'll try to write several times
    for ( my $retry = 0 ; $retry < $AMAZON_S3_WRITE_ATTEMPTS ; ++$retry )
    {
        if ( $retry > 0 )
        {
            say STDERR "Retrying ($retry)...";
        }

        eval {

            # Store; will die() on failure
            $object = $self->_object_for_object_id( $object_id );
            $object->put( $content_to_store );
            $write_was_successful = 1;

        };

        if ( $@ )
        {
            say STDERR "Attempt to write object ID $object_id didn't succeed because: $@";
        }
        else
        {
            last;
        }
    }

    unless ( $write_was_successful )
    {
        confess "Unable to write object ID $object_id to Amazon S3 after $AMAZON_S3_WRITE_ATTEMPTS retries.";
    }

    return 's3:' . $object->key;
}

# Moose method
sub fetch_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    $self->_initialize_s3_or_die();

    if ( $AMAZON_S3_CHECK_IF_EXISTS_BEFORE_FETCHING )
    {
        unless ( $self->content_exists( $db, $object_id, $object_path ) )
        {
            confess "AmazonS3: object ID $object_id does not exist.";
        }
    }

    my $object;
    my $gzipped_content;

    # S3 sometimes times out when reading, so we'll try to read several times
    for ( my $retry = 0 ; $retry < $AMAZON_S3_READ_ATTEMPTS ; ++$retry )
    {
        if ( $retry > 0 )
        {
            say STDERR "Retrying ($retry)...";
        }

        eval {

            # Read; will die() on failure
            $object          = $self->_object_for_object_id( $object_id );
            $gzipped_content = $object->get;

        };

        if ( $@ )
        {
            say STDERR "Attempt to read object ID $object_id didn't succeed because: $@";
        }
        else
        {
            last;
        }
    }

    unless ( defined $gzipped_content )
    {
        confess "Unable to read object ID $object_id from Amazon S3 after $AMAZON_S3_READ_ATTEMPTS retries.";
    }

    # Gunzip + decode
    my $decoded_content;
    eval { $decoded_content = MediaWords::Util::Compress::gunzip_and_decode( $gzipped_content ); };
    if ( $@ or ( !defined $decoded_content ) )
    {
        confess "Unable to uncompress object ID $object_id: $@";
    }

    return \$decoded_content;
}

no Moose;    # gets rid of scaffolding

1;
