package MediaWords::KeyValueStore::CachedAmazonS3;

# locally cached Amazon S3 key-value storage

use strict;
use warnings;

use Moose;
extends 'MediaWords::KeyValueStore::AmazonS3';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use CHI;
use Readonly;

# Default compression method for cache
Readonly my $CACHE_DEFAULT_COMPRESSION_METHOD => $MediaWords::KeyValueStore::COMPRESSION_GZIP;

# Configuration
has '_conf_cache_root_dir' => ( is => 'rw' );

# CHI
has '_chi' => ( is => 'rw' );

# Process PID (to prevent forks attempting to clone the Net::Amazon::S3 accessor objects)
has '_pid' => ( is => 'rw', default => 0 );

# Compression method to use
has '_conf_cache_compression_method' => ( is => 'rw' );

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    my $cache_root_dir = $args->{ cache_root_dir };
    my $cache_compression_method = $args->{ cache_compression_method } || $CACHE_DEFAULT_COMPRESSION_METHOD;

    unless ( $cache_root_dir )
    {
        LOGCONFESS "Please provide 'cache_root_dir' argument.";
    }
    unless ( -d $cache_root_dir )
    {
        unless ( mkdir( $cache_root_dir ) )
        {
            LOGCONFESS "Unable to create cache directory '$cache_root_dir': $!";
        }
    }
    unless ( $self->compression_method_is_valid( $cache_compression_method ) )
    {
        LOGCONFESS "Unsupported cache compression method '$cache_compression_method'";
    }

    $self->_conf_cache_root_dir( $cache_root_dir );
    $self->_conf_cache_compression_method( $cache_compression_method );

    $self->_pid( $$ );
}

sub _initialize_chi_or_die($)
{
    my ( $self ) = @_;

    if ( $self->_pid == $$ and $self->_chi )
    {
        # Already initialized on the very same process
        return;
    }

    $self->_chi(
        CHI->new(
            driver   => 'File',
            root_dir => $self->_conf_cache_root_dir,

            # No "expires_in", "cache_size" or "max_size" here because CHI's
            # "File" driver sometimes throws assertions when trying to
            # invalidate old objects. Instead, use:
            #
            #     find data/s3_downloads/ -type f -mtime +3 -exec rm {} \;
        )
    );

    # Save PID
    $self->_pid( $$ );

    DEBUG "CachedAmazonS3: Initialized cached Amazon S3 storage for PID $$.";
}

sub _try_storing_object_in_cache($$$)
{
    my ( $self, $object_id, $content_ref ) = @_;

    $self->_initialize_chi_or_die();

    eval {
        # Compress
        my $content_to_store;
        eval {
            $content_to_store = $self->compress_data_for_method( $$content_ref, $self->_conf_cache_compression_method ); };
        if ( $@ or ( !defined $content_to_store ) )
        {
            LOGCONFESS "Unable to compress object ID $object_id: $@";
        }

        $self->_chi->set( $object_id, $content_to_store );
    };
    if ( $@ )
    {
        # Don't die() if we were unable to cache the object
        WARN "Caching object $object_id failed: $@";
    }
}

sub _try_retrieving_object_from_cache($$)
{
    my ( $self, $object_id ) = @_;

    $self->_initialize_chi_or_die();

    my $decoded_content;
    eval {
        my $compressed_content = $self->_chi->get( $object_id );
        if ( defined $compressed_content )
        {
            # Uncompress
            my $decoded_content;
            eval {
                $decoded_content =
                  $self->uncompress_data_for_method( $compressed_content, $self->_conf_cache_compression_method );
            };
            if ( $@ or ( !defined $decoded_content ) )
            {
                LOGCONFESS "Unable to uncompress object ID $object_id: $@";
            }
        }
    };
    if ( $@ )
    {
        # Don't die() if we were unable to restore object from cache
        WARN "Restoring object $object_id from cache failed: $@";
    }

    if ( defined $decoded_content )
    {
        # Something was found in cache
        return \$decoded_content;
    }
    else
    {
        return undef;
    }
}

# Moose method
sub content_exists($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    $self->_initialize_chi_or_die();

    if ( defined $self->_try_retrieving_object_from_cache( $object_id ) )
    {
        # Key is cached, that means it exists on S3 too
        return 1;
    }
    else
    {
        return $self->SUPER::content_exists( $db, $object_id, $object_path );
    }
}

# Moose method
sub remove_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    $self->_initialize_chi_or_die();

    eval { $self->_chi->remove( $object_id ); };
    if ( $@ )
    {
        # Don't die() if we were unable to remove object from cache
        WARN "Removing object $object_id from cache failed: $@";
    }

    return $self->SUPER::remove_content( $db, $object_id, $object_path );
}

# Moose method
sub store_content($$$$)
{
    my ( $self, $db, $object_id, $content_ref ) = @_;

    $self->_initialize_chi_or_die();

    my $path = $self->SUPER::store_content( $db, $object_id, $content_ref );

    # If we got to this point, object got stored in S3 successfully

    $self->_try_storing_object_in_cache( $object_id, $content_ref );

    return $path;
}

# Moose method
sub fetch_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    $self->_initialize_chi_or_die();

    my $cached_content_ref = $self->_try_retrieving_object_from_cache( $object_id );
    if ( defined $cached_content_ref )
    {
        return $cached_content_ref;
    }
    else
    {

        # Cache the retrieved object because we might need it soon
        my $content_ref = $self->SUPER::fetch_content( $db, $object_id, $object_path );

        if ( defined $content_ref )
        {
            $self->_try_storing_object_in_cache( $object_id, $content_ref );
        }

        return $content_ref;
    }
}

no Moose;    # gets rid of scaffolding

1;
