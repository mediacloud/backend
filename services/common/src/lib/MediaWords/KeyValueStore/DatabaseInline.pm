package MediaWords::KeyValueStore::DatabaseInline;

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Text;

# Import DatabaseInlineStore class
import_python_module( __PACKAGE__, 'mediawords.key_value_store.database_inline' );

# DatabaseInlineStore instance
has '_python_store' => ( is => 'rw' );

sub BUILD($$)
{
    my ( $self, $args ) = @_;

    $self->_python_store( MediaWords::KeyValueStore::DatabaseInline::DatabaseInlineStore->new() );
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
