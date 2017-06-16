package MediaWords::KeyValueStore::PostgreSQL;

# class for storing / loading objects (raw downloads,
# CoreNLP annotator results, ...) to / from PostgreSQL

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2015";
use MediaWords::DB;
use MediaWords::CommonLibs;
use MediaWords::Util::Compress;

# Default compression method for PostgreSQL
Readonly my $POSTGRESQL_DEFAULT_COMPRESSION_METHOD => $MediaWords::KeyValueStore::COMPRESSION_GZIP;

# Configuration
has '_conf_table' => ( is => 'rw' );

# Compression method to use
has '_conf_compression_method' => ( is => 'rw' );

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    my $table = $args->{ table };
    my $compression_method = $args->{ compression_method } || $POSTGRESQL_DEFAULT_COMPRESSION_METHOD;

    unless ( $table )
    {
        die "Database table to store objects in is unset.";
    }
    unless ( $self->compression_method_is_valid( $compression_method ) )
    {
        LOGCONFESS "Unsupported compression method '$compression_method'";
    }

    $self->_conf_table( $table );
    $self->_conf_compression_method( $compression_method );
}

# Moose method
sub store_content($$$$)
{
    my ( $self, $db, $object_id, $content_ref ) = @_;

    my $table = $self->_conf_table;

    # Compress
    my $content_to_store;
    eval { $content_to_store = $self->compress_data_for_method( $$content_ref, $self->_conf_compression_method ); };
    if ( $@ or ( !defined $content_to_store ) )
    {
        LOGCONFESS "Unable to compress object ID $object_id: $@";
    }

    my $sth = $db->prepare(
        <<"SQL",
        INSERT INTO $table (object_id, raw_data)
        VALUES (?, ?)
        ON CONFLICT (object_id) DO UPDATE
            SET raw_data = EXCLUDED.raw_data
SQL
    );
    $sth->bind( 1, $object_id );
    $sth->bind_bytea( 2, $content_to_store );
    $sth->execute();

    my $path = 'postgresql:' . $table;
    return $path;
}

# Moose method
sub fetch_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    unless ( defined $object_id )
    {
        LOGCONFESS "Object ID is undefined.";
    }

    my $table = $self->_conf_table;

    my $compressed_content = $db->query(
        <<"EOF",
        SELECT raw_data
        FROM $table
        WHERE object_id = ?
EOF
        $object_id
    )->flat;

    unless ( defined $compressed_content->[ 0 ] )
    {
        LOGCONFESS "Object with ID $object_id was not found in '$table' table.";
    }

    $compressed_content = $compressed_content->[ 0 ];

    # Inline::Python returns Python's 'bytes' as arrayref
    if ( ref( $compressed_content ) eq ref( [] ) )
    {
        $compressed_content = join( '', @{ $compressed_content } );
    }

    if ( $compressed_content eq '' )
    {
        LOGCONFESS "Object's with ID $object_id data is empty in '$table' table.";
    }

    # Uncompress + decode
    unless ( defined $compressed_content and $compressed_content ne '' )
    {
        # PostgreSQL might return an empty string on some cases of corrupt
        # data (technically), but an empty string can't be a valid Gzip/Bzip2
        # archive, so we're checking if we're about to attempt to decompress an
        # empty string
        LOGCONFESS "Compressed data is empty for object $object_id.";
    }

    # Uncompress
    my $decoded_content;
    eval { $decoded_content = $self->uncompress_data_for_method( $compressed_content, $self->_conf_compression_method ); };
    if ( $@ or ( !defined $decoded_content ) )
    {
        LOGCONFESS "Unable to uncompress object ID $object_id: $@";
    }

    return \$decoded_content;
}

# Moose method
sub remove_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    my $table = $self->_conf_table;

    $db->query(
        <<"EOF",
        DELETE FROM $table
        WHERE object_id = ?
EOF
        $object_id
    );

    return 1;
}

# Moose method
sub content_exists($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    my $table = $self->_conf_table;

    my $object_exists = $db->query(
        <<"EOF",
        SELECT 1
        FROM $table
        WHERE object_id = ?
EOF
        $object_id
    )->flat;

    if ( $object_exists->[ 0 ] )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

no Moose;    # gets rid of scaffolding

1;
