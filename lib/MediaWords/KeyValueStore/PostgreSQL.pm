package MediaWords::KeyValueStore::PostgreSQL;

# class for storing / loading objects (raw downloads, CoreNLP annotator results, ...) to / from PostgreSQL

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use DBD::Pg qw(:pg_types);

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
sub store_content($$$$)
{
    my ( $self, $db, $object_id, $content_ref ) = @_;

    my $table_name = $self->_conf_table_name;

    # Encode + gzip
    my $content_to_store = $self->encode_and_compress( $content_ref, $object_id );

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
sub fetch_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    my $table_name = $self->_conf_table_name;

    my $gzipped_content = $db->query(
        <<"EOF",
        SELECT raw_data
        FROM $table_name
        WHERE object_id = ?
EOF
        $object_id
    )->flat;

    unless ( $gzipped_content->[ 0 ] )
    {
        die "Object with ID $object_id was not found in '$table_name' table.\n";
    }

    $gzipped_content = $gzipped_content->[ 0 ];

    # Gunzip + decode
    my $decoded_content = $self->uncompress_and_decode( \$gzipped_content, $object_id );

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
