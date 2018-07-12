package MediaWords::KeyValueStore::CachedAmazonS3;

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Text;

# Import AmazonS3Store class
import_python_module( __PACKAGE__, 'mediawords.key_value_store.cached_amazon_s3' );

# AmazonS3Store instance
has '_python_store' => ( is => 'rw' );

sub BUILD($$)
{
    my ( $self, $args ) = @_;

    my $access_key_id            = $args->{ access_key_id };
    my $secret_access_key        = $args->{ secret_access_key };
    my $bucket_name              = $args->{ bucket_name };
    my $directory_name           = $args->{ directory_name };
    my $compression_method       = $args->{ compression_method };
    my $cache_table              = $args->{ cache_table };
    my $cache_compression_method = $args->{ cache_compression_method };

    $self->_python_store(
        MediaWords::KeyValueStore::CachedAmazonS3::CachedAmazonS3Store->new(
            $access_key_id,              #
            $secret_access_key,          #
            $bucket_name,                #
            $directory_name,             #
            $cache_table,                #
            $compression_method,         #
            $cache_compression_method    #
        )
    );
}

sub store_content($$$$)
{
    my ( $self, $db, $object_id, $content ) = @_;

    # Python handler will encode Perl's strings itself

    return $self->_python_store->store_content( $db, $object_id, $content );
}

sub fetch_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    my $content = $self->_python_store->fetch_content( $db, $object_id, $object_path );

    # Inline::Python returns Python's 'bytes' as arrayref
    if ( ref( $content ) eq ref( [] ) )
    {
        $content = join( '', @{ $content } );
    }

    my $decoded_content = MediaWords::Util::Text::decode_from_utf8( $content );

    return $decoded_content;
}

sub remove_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    return $self->_python_store->remove_content( $db, $object_id, $object_path );
}

sub content_exists($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    return $self->_python_store->content_exists( $db, $object_id, $object_path );
}

no Moose;    # gets rid of scaffolding

1;
