package MediaWords::KeyValueStore::PostgreSQL;

# class for storing / loading objects (raw downloads,
# CoreNLP annotator results, ...) to / from PostgreSQL

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::Util::Compress;
use DBD::Pg qw(:pg_types);
use Carp;

# Configuration
has '_conf_table_name' => ( is => 'rw' );

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    # Get arguments
    unless ( $args->{ table_name } )
    {
        die "Please provide 'table_name' argument.\n";
    }
    my $table_name = $args->{ table_name };

    # Store configuration
    $self->_conf_table_name( $table_name );
}

# Moose method
sub store_content($$$$;$)
{
    my ( $self, $db, $object_id, $content_ref, $use_bzip2_instead_of_gzip ) = @_;

    my $table_name = $self->_conf_table_name;

    # Encode + compress
    my $content_to_store;
    eval {
        if ( $use_bzip2_instead_of_gzip )
        {
            $content_to_store = MediaWords::Util::Compress::encode_and_bzip2( $$content_ref );
        }
        else
        {
            $content_to_store = MediaWords::Util::Compress::encode_and_gzip( $$content_ref );
        }
    };
    if ( $@ or ( !defined $content_to_store ) )
    {
        die "Unable to compress object ID $object_id: $@";
    }

    my $use_transaction = $db->dbh->{ AutoCommit };

    # "Upsert" the object
    $db->begin_work if ( $use_transaction );

    my $sth;

    $sth = $db->dbh->prepare(
        <<"EOF",
    	UPDATE $table_name
    	SET raw_data = ?
    	WHERE object_id = ?
EOF
    );
    $sth->bind_param( 1, $content_to_store, { pg_type => DBD::Pg::PG_BYTEA } );
    $sth->bind_param( 2, $object_id );
    $sth->execute();

    $sth = $db->dbh->prepare(
        <<"EOF",
    	INSERT INTO $table_name (object_id, raw_data)
			SELECT ?, ?
			WHERE NOT EXISTS (
				SELECT 1
				FROM $table_name
				WHERE object_id = ?
			)
EOF
    );
    $sth->bind_param( 1, $object_id );
    $sth->bind_param( 2, $content_to_store, { pg_type => DBD::Pg::PG_BYTEA } );
    $sth->bind_param( 3, $object_id );
    $sth->execute();

    $db->commit if ( $use_transaction );

    my $path = 'postgresql:' . $table_name;
    return $path;
}

# Moose method
sub fetch_content($$$;$$)
{
    my ( $self, $db, $object_id, $object_path, $use_bunzip2_instead_of_gunzip ) = @_;

    unless ( defined $object_id )
    {
        die "Object ID is undefined.\n";
    }

    my $table_name = $self->_conf_table_name;

    my $compressed_content = $db->query(
        <<"EOF",
        SELECT raw_data
        FROM $table_name
        WHERE object_id = ?
EOF
        $object_id
    )->flat;

    unless ( $compressed_content->[ 0 ] )
    {
        die "Object with ID $object_id was not found in '$table_name' table.\n";
    }

    $compressed_content = $compressed_content->[ 0 ];

    # Uncompress + decode
    unless ( defined $compressed_content and $compressed_content ne '' )
    {
        # PostgreSQL might return an empty string on some cases of corrupt
        # data (technically), but an empty string can't be a valid Gzip/Bzip2
        # archive, so we're checking if we're about to attempt to decompress an
        # empty string
        confess "Compressed data is empty for object $object_id.\n";
    }

    my $decoded_content;
    eval {
        if ( $use_bunzip2_instead_of_gunzip )
        {
            $decoded_content = MediaWords::Util::Compress::bunzip2_and_decode( $compressed_content );
        }
        else
        {
            $decoded_content = MediaWords::Util::Compress::gunzip_and_decode( $compressed_content );
        }
    };
    if ( $@ or ( !defined $decoded_content ) )
    {
        die "Unable to uncompress object ID $object_id: $@";
    }

    return \$decoded_content;
}

# Moose method
sub remove_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    my $table_name = $self->_conf_table_name;

    $db->query(
        <<"EOF",
        DELETE FROM $table_name
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

    my $table_name = $self->_conf_table_name;

    my $object_exists = $db->query(
        <<"EOF",
        SELECT 1
        FROM $table_name
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
