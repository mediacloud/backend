package MediaWords::KeyValueStore::CachedAmazonS3;

# locally cached Amazon S3 key-value storage

use strict;
use warnings;

use Moose;
extends 'MediaWords::KeyValueStore::AmazonS3';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use Readonly;

# Default compression method for cache
Readonly my $CACHE_DEFAULT_COMPRESSION_METHOD => $MediaWords::KeyValueStore::COMPRESSION_GZIP;

# Process PID (to prevent forks attempting to clone the Net::Amazon::S3 accessor objects)
has '_pid' => ( is => 'rw', default => 0 );

# Table to use for caching objects
has '_conf_cache_table' => ( is => 'rw' );

# Compression method to use
has '_conf_cache_compression_method' => ( is => 'rw' );

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    my $cache_table = $args->{ cache_table };
    unless ( $cache_table )
    {
        LOGCONFESS "Cache table is unset.";
    }

    my $cache_compression_method = $args->{ cache_compression_method } || $CACHE_DEFAULT_COMPRESSION_METHOD;
    unless ( $self->compression_method_is_valid( $cache_compression_method ) )
    {
        LOGCONFESS "Unsupported cache compression method '$cache_compression_method'";
    }

    $self->_conf_cache_table( $cache_table );
    $self->_conf_cache_compression_method( $cache_compression_method );

    $self->_pid( $$ );
}

sub _try_storing_object_in_cache($$$$)
{
    my ( $self, $db, $object_id, $content_ref ) = @_;

    eval {
        my $content_to_store;
        eval {
            $content_to_store = $self->compress_data_for_method( $$content_ref, $self->_conf_cache_compression_method ); };
        if ( $@ or ( !defined $content_to_store ) )
        {
            LOGCONFESS "Unable to compress object ID $object_id: $@";
        }

        my $cache_table = $self->_conf_cache_table;
        my $sth         = $db->prepare(
            <<"SQL",
            INSERT INTO $cache_table (object_id, raw_data)
            VALUES (?, ?)
            ON CONFLICT (object_id) DO UPDATE
                SET raw_data = EXCLUDED.raw_data
SQL
        );
        $sth->bind( 1, $object_id );
        $sth->bind_bytea( 2, $content_to_store );
        $sth->execute();

    };
    if ( $@ )
    {
        # Don't die() if we were unable to cache the object
        WARN "Caching object $object_id failed: $@";
    }
}

sub _try_retrieving_object_from_cache($$$)
{
    my ( $self, $db, $object_id ) = @_;

    my $decoded_content;
    eval {

        my $cache_table = $self->_conf_cache_table;
        my ( $compressed_content ) = $db->query(
            <<"SQL",
            SELECT raw_data
            FROM $cache_table
            WHERE object_id = ?
SQL
            $object_id
        )->flat;

        # Inline::Python returns Python's 'bytes' as arrayref
        if ( ref( $compressed_content ) eq ref( [] ) )
        {
            $compressed_content = join( '', @{ $compressed_content } );
        }

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

    if ( defined $self->_try_retrieving_object_from_cache( $db, $object_id ) )
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

    eval {

        my $cache_table = $self->_conf_cache_table;
        $db->query(
            <<SQL,
            DELETE FROM $cache_table
            WHERE object_id = ?
SQL
            $object_id
        );

    };
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

    my $path = $self->SUPER::store_content( $db, $object_id, $content_ref );

    # If we got to this point, object got stored in S3 successfully

    $self->_try_storing_object_in_cache( $db, $object_id, $content_ref );

    return $path;
}

# Moose method
sub fetch_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    my $cached_content_ref = $self->_try_retrieving_object_from_cache( $db, $object_id );
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
            $self->_try_storing_object_in_cache( $db, $object_id, $content_ref );
        }

        return $content_ref;
    }
}

no Moose;    # gets rid of scaffolding

1;
