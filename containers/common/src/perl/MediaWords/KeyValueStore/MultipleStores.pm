package MediaWords::KeyValueStore::MultipleStores;

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Text;

# Import MultipleStoresStore class
import_python_module( __PACKAGE__, 'mediawords.key_value_store.multiple_stores' );

# MultipleStoresStore instance
has '_python_store' => ( is => 'rw' );

sub BUILD($$)
{
    my ( $self, $args ) = @_;

    my $perl_stores_for_reading = $args->{ stores_for_reading };
    my $perl_stores_for_writing = $args->{ stores_for_writing };

    my $stores_for_reading = [];
    my $stores_for_writing = [];

    foreach my $store ( @{ $perl_stores_for_reading } )
    {
        push( @{ $stores_for_reading }, $store->_python_store );
    }
    foreach my $store ( @{ $perl_stores_for_writing } )
    {
        push( @{ $stores_for_writing }, $store->_python_store );
    }

    $self->_python_store(
        MediaWords::KeyValueStore::MultipleStores::MultipleStoresStore->new(
            $stores_for_reading,    #
            $stores_for_writing,    #
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
