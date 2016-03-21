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
use DBD::Pg qw(:pg_types);
use Carp;

# Configuration
has '_conf_database_label' => ( is => 'rw' );
has '_conf_table'          => ( is => 'rw' );

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    unless ( $args->{ database_label } or $args->{ table } )
    {
        die "Set database label and / or table to use; I'm nervous to use the main database and table as defaults.";
    }

    my $database_label = $args->{ database_label };
    $self->_conf_database_label( $database_label );

    if ( defined $database_label )
    {
        unless ( grep { $_ eq $database_label } MediaWords::DB::get_db_labels() )
        {
            die "No such database label '$database_label'";
        }
    }

    # Table name either from constructor arguments or from database label's "table" key
    my $table = $args->{ table };
    unless ( $table )
    {
        my $connect_settings = MediaWords::DB::connect_settings( $database_label );
        $table = $connect_settings->{ table };
    }

    unless ( $table )
    {
        die "Table is unset (it wasn't in the database settings neither it was passed as a parameter).";
    }

    $self->_conf_table( $table );
}

sub _db($)
{
    my $self = shift;

    my $db = MediaWords::DB::connect_to_db( $self->_conf_database_label );

    say STDERR "PostgreSQL: Connected to PostgreSQL label '" . ( $self->_conf_database_label // 'undef' ) . "'.";

    return $db;
}

# Moose method
sub store_content($$$$;$)
{
    my ( $self, $_not_used_db, $object_id, $content_ref, $use_bzip2_instead_of_gzip ) = @_;

    my $db = $self->_db();

    my $table = $self->_conf_table;

    # my $db    = $self->_db;

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
        confess "Unable to compress object ID $object_id: $@";
    }

    my $use_transaction = $db->dbh->{ AutoCommit };

    # "Upsert" the object
    $db->begin_work if ( $use_transaction );

    my $sth;

    $sth = $db->dbh->prepare(
        <<"EOF",
    	UPDATE $table
    	SET raw_data = ?
    	WHERE object_id = ?
EOF
    );
    $sth->bind_param( 1, $content_to_store, { pg_type => DBD::Pg::PG_BYTEA } );
    $sth->bind_param( 2, $object_id );
    $sth->execute();

    $sth = $db->dbh->prepare(
        <<"EOF",
    	INSERT INTO $table (object_id, raw_data)
			SELECT ?, ?
			WHERE NOT EXISTS (
				SELECT 1
				FROM $table
				WHERE object_id = ?
			)
EOF
    );
    $sth->bind_param( 1, $object_id );
    $sth->bind_param( 2, $content_to_store, { pg_type => DBD::Pg::PG_BYTEA } );
    $sth->bind_param( 3, $object_id );
    $sth->execute();

    $db->commit if ( $use_transaction );

    my $path = 'postgresql:' . $table;
    return $path;
}

# Moose method
sub fetch_content($$$;$$)
{
    my ( $self, $_not_used_db, $object_id, $object_path, $use_bunzip2_instead_of_gunzip ) = @_;

    my $db = $self->_db();

    unless ( defined $object_id )
    {
        confess "Object ID is undefined.";
    }

    my $table = $self->_conf_table;

    # my $db    = $self->_db;

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
        confess "Object with ID $object_id was not found in '$table' table.";
    }

    $compressed_content = $compressed_content->[ 0 ];
    if ( $compressed_content eq '' )
    {
        confess "Object's with ID $object_id data is empty in '$table' table.";
    }

    # Uncompress + decode
    unless ( defined $compressed_content and $compressed_content ne '' )
    {
        # PostgreSQL might return an empty string on some cases of corrupt
        # data (technically), but an empty string can't be a valid Gzip/Bzip2
        # archive, so we're checking if we're about to attempt to decompress an
        # empty string
        confess "Compressed data is empty for object $object_id.";
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
        confess "Unable to uncompress object ID $object_id: $@";
    }

    return \$decoded_content;
}

# Moose method
sub remove_content($$$;$)
{
    my ( $self, $_not_used_db, $object_id, $object_path ) = @_;

    my $db = $self->_db();

    my $table = $self->_conf_table;

    # my $db    = $self->_db;

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
    my ( $self, $_not_used_db, $object_id, $object_path ) = @_;

    my $db = $self->_db();

    my $table = $self->_conf_table;

    #my $db    = $self->_db;

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
