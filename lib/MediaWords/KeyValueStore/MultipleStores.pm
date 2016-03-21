package MediaWords::KeyValueStore::MultipleStores;

# handler for multiple key-value stores

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use Carp;

# Stores to try reading from / writing to
has '_stores_for_reading' => ( is => 'rw' );
has '_stores_for_writing' => ( is => 'rw' );

sub BUILD($$)
{
    my ( $self, $args ) = @_;

    # Caller might choose to use only one list of stores if it's going to only read or write
    my $stores_for_reading = $args->{ stores_for_reading };
    my $stores_for_writing = $args->{ stores_for_writing };

    unless ( $stores_for_reading or $stores_for_writing )
    {
        confess "At least one list of stores should be defined.";
    }
    unless ( ref( $stores_for_reading ) eq ref( [] ) or ref( $stores_for_writing ) eq ref( [] ) )
    {
        confess "At least one list of stores stores should be an arrayref.";
    }

    my @all_stores;
    if ( $stores_for_reading )
    {
        push( @all_stores, @{ $stores_for_reading } );
    }
    if ( $stores_for_writing )
    {
        push( @all_stores, @{ $stores_for_writing } );
    }

    if ( scalar( @all_stores ) == 0 )
    {
        confess "At least one store for reading / writing should be present.";
    }

    foreach my $store ( @all_stores )
    {
        # $store->isa() doesn't seem to work for whatever reason
        unless ( ref( $store ) =~ /^MediaWords::KeyValueStore/ )
        {
            confess 'Store ' . ref( $store ) . ' is not of key-value store type.';
        }
    }

    $self->_stores_for_reading( $stores_for_reading );
    $self->_stores_for_writing( $stores_for_writing );
}

# Store content in all of the stores
# die() if storing in one of the stores failed
sub store_content($$$$)
{
    my ( $self, $db, $object_id, $content_ref ) = @_;

    my $last_store_path;

    unless ( $self->_stores_for_writing and scalar( @{ $self->_stores_for_writing } ) > 0 )
    {
        confess "List of stores for writing object $object_id is empty.";
    }

    foreach my $store ( @{ $self->_stores_for_writing } )
    {
        eval {
            $last_store_path = $store->store_content( $db, $object_id, $content_ref );
            unless ( $last_store_path )
            {
                confess "Storing object $object_id to " . ref( $store ) . " succeeded, but the returned path is empty.";
            }
        };
        if ( $@ )
        {
            my $store_error_message = $@;
            confess "Error while saving object $object_id to store " . ref( $store ) . ": $@";
        }
    }

    unless ( $last_store_path )
    {
        confess "Storing object $object_id to all stores succeeded, but the returned path is empty.";
    }

    return $last_store_path;
}

# Fetch content from any of the stores that might have it
# die() if none of the stores have it
sub fetch_content($$$$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    my $content_ref;

    my @errors;

    unless ( $self->_stores_for_reading and scalar( @{ $self->_stores_for_reading } ) > 0 )
    {
        confess "List of stores for reading object $object_id is empty.";
    }

    foreach my $store ( @{ $self->_stores_for_reading } )
    {
        eval {
            $content_ref = $store->fetch_content( $db, $object_id, $object_path );
            unless ( $content_ref )
            {
                confess "Fetching object $object_id from " .
                  ref( $store ) . " succeeded, but the returned content ref is empty.";
            }
        };
        if ( $@ )
        {
            # Silently skip through errors and die() only if content wasn't found anywhere
            push( @errors, "Error fetching object $object_id from " . ref( $store ) . ": $@" );
        }
        else
        {
            last;
        }
    }

    unless ( $content_ref )
    {
        confess "All stores failed while fetching object $object_id; errors: " . join( "\n", @errors );
    }

    return $content_ref;
}

# Remove content from all of the stores
# die() if removal from at least one of the stores failed
sub remove_content($$$$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    unless ( $self->_stores_for_writing and scalar( @{ $self->_stores_for_writing } ) > 0 )
    {
        confess "List of stores for writing object $object_id is empty.";
    }

    foreach my $store ( @{ $self->_stores_for_writing } )
    {
        eval {
            my $removal_succeeded = $store->remove_content( $db, $object_id, $object_path );
            unless ( $removal_succeeded )
            {
                confess "Removing object $object_id to " . ref( $store ) . " succeeded, but the store didn't return true.";
            }
        };
        if ( $@ )
        {
            my $store_error_message = $@;
            confess "Error while removing object $object_id from store " . ref( $store ) . ": $@";
        }
    }

    return 1;
}

# Test if content exists in at least one of the stores
# die() if at least one of the stores failed testing for content
sub content_exists($$$$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    unless ( $self->_stores_for_reading and scalar( @{ $self->_stores_for_reading } ) > 0 )
    {
        confess "List of stores for reading object $object_id is empty.";
    }

    my $exists = 0;
    foreach my $store ( @{ $self->_stores_for_reading } )
    {
        eval { $exists = $store->content_exists( $db, $object_id, $object_path ); };
        if ( $@ )
        {
            confess "Error while testing whether object $object_id exists in store " . ref( $store ) . ": $@";
        }
        if ( $exists )
        {
            return 1;
        }
    }

    return 0;
}

no Moose;    # gets rid of scaffolding

1;
