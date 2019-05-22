package MediaWords::KeyValueStore::PostgreSQL;

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Text;

# Import PostgreSQLStore class
import_python_module( __PACKAGE__, 'mediawords.key_value_store.postgresql' );

# PostgreSQLStore instance
has '_python_store' => ( is => 'rw' );

sub BUILD($$)
{
    my ( $self, $args ) = @_;

    my $table              = $args->{ table };
    my $compression_method = $args->{ compression_method };

    $self->_python_store(
        MediaWords::KeyValueStore::PostgreSQL::PostgreSQLStore->new(
            $table,                #
            $compression_method    #
        )
    );
}

sub store_content($$$$)
{
    my ( $self, $db, $object_id, $content ) = @_;

    # Python handler will encode Perl's strings itself

    return $self->_python_store->store_content( $db, $object_id, $content );
}

sub fetch_content($$$;$$)
{
    my ( $self, $db, $object_id, $object_path, $raw ) = @_;

    my $content = $self->_python_store->fetch_content( $db, $object_id, $object_path );

    # Inline::Python returns Python's 'bytes' as arrayref
    if ( ref( $content ) eq ref( [] ) )
    {
        $content = join( '', @{ $content } );
    }

    my $decoded_content;
    if ( $raw ) {
        $decoded_content = $content;
    } else {
        $decoded_content = MediaWords::Util::Text::decode_from_utf8( $content );
    }

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
