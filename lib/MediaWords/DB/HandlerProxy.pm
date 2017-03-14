package MediaWords::DB::HandlerProxy;

# Proxy to DatabaseHandler Python implementation. Makes return values writable.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub new
{
    my ( $class, $db ) = @_;

    my $self = {};
    bless $self, $class;

    $self->{ _db } = $db;

    return $self;
}

sub disconnect
{
    my $self = shift;

    $self->{ _db }->disconnect( @_ );
    delete $self->{ _db };
}

sub dbh
{
    my $self = shift;
    return $self->{ _db }->dbh( @_ );
}

sub schema_is_up_to_date
{
    my $self = shift;
    return $self->{ _db }->schema_is_up_to_date( @_ );
}

{

    package MediaWords::DB::HandlerProxy::ResultProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    sub new
    {
        my ( $class, $python_result ) = @_;

        my $self = {};
        bless $self, $class;

        $self->{ _python_result } = $python_result;

        return $self;
    }

    sub columns
    {
        my $self           = shift;
        my $return_value   = $self->{ _python_result }->columns( @_ );
        my $writable_value = python_deep_copy( $return_value );
        return wantarray ? @{ $writable_value } : $writable_value;
    }

    sub rows
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->rows( @_ );
        return python_deep_copy( $return_value );
    }

    sub array
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->array( @_ );
        return python_deep_copy( $return_value );
    }

    sub hash
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->hash( @_ );
        return python_deep_copy( $return_value );
    }

    sub flat
    {
        my $self           = shift;
        my $return_value   = $self->{ _python_result }->flat( @_ );
        my $writable_value = python_deep_copy( $return_value );
        return wantarray ? @{ $writable_value } : $writable_value;
    }

    sub hashes
    {
        my $self           = shift;
        my $return_value   = $self->{ _python_result }->hashes( @_ );
        my $writable_value = python_deep_copy( $return_value );
        return wantarray ? @{ $writable_value } : $writable_value;
    }

    sub text
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->text( @_ );
        return python_deep_copy( $return_value );
    }

    1;
}

sub query
{
    my $self = shift;

    my $python_result = $self->{ _db }->query( @_ );
    return MediaWords::DB::HandlerProxy::ResultProxy->new( $python_result );
}

sub run_block_with_large_work_mem
{
    my $self = shift;
    return $self->{ _db }->run_block_with_large_work_mem( @_ );
}

sub execute_with_large_work_mem
{
    my $self = shift;
    return $self->{ _db }->execute_with_large_work_mem( @_ );
}

sub primary_key_column
{
    my $self         = shift;
    my $return_value = $self->{ _db }->primary_key_column( @_ );
    return python_deep_copy( $return_value );
}

sub find_by_id
{
    my $self         = shift;
    my $return_value = $self->{ _db }->find_by_id( @_ );
    return python_deep_copy( $return_value );
}

sub require_by_id
{
    my $self         = shift;
    my $return_value = $self->{ _db }->require_by_id( @_ );
    return python_deep_copy( $return_value );
}

sub select
{
    my $self          = shift;
    my $python_result = $self->{ _db }->select( @_ );
    return MediaWords::DB::HandlerProxy::ResultProxy->new( $python_result );
}

sub update_by_id($$$$)
{
    my $self = shift;
    return $self->{ _db }->update_by_id( @_ );
}

sub delete_by_id
{
    my $self = shift;
    return $self->{ _db }->delete_by_id( @_ );
}

sub insert
{
    my $self         = shift;
    my $return_value = $self->{ _db }->insert( @_ );
    return python_deep_copy( $return_value );
}

sub create
{
    my $self         = shift;
    my $return_value = $self->{ _db }->create( @_ );
    return python_deep_copy( $return_value );
}

sub find_or_create
{
    my $self         = shift;
    my $return_value = $self->{ _db }->find_or_create( @_ );
    return python_deep_copy( $return_value );
}

sub query_paged_hashes
{
    my $self = shift;
    return $self->{ _db }->query_paged_hashes( @_ );
}

sub get_temporary_ids_table
{
    my $self         = shift;
    my $return_value = $self->{ _db }->get_temporary_ids_table( @_ );
    return python_deep_copy( $return_value );
}

sub begin
{
    my $self = shift;
    return $self->{ _db }->begin( @_ );
}

sub begin_work
{
    my $self = shift;
    return $self->{ _db }->begin_work( @_ );
}

sub commit
{
    my $self = shift;
    return $self->{ _db }->commit( @_ );
}

sub rollback
{
    my $self = shift;
    return $self->{ _db }->rollback( @_ );
}

sub quote
{
    my $self         = shift;
    my $return_value = $self->{ _db }->quote( @_ );
    return python_deep_copy( $return_value );
}

sub quote_bool
{
    my $self         = shift;
    my $return_value = $self->{ _db }->quote_bool( @_ );
    return python_deep_copy( $return_value );
}

sub quote_varchar
{
    my $self         = shift;
    my $return_value = $self->{ _db }->quote_varchar( @_ );
    return python_deep_copy( $return_value );
}

sub quote_date
{
    my $self         = shift;
    my $return_value = $self->{ _db }->quote_date( @_ );
    return python_deep_copy( $return_value );
}

sub quote_timestamp
{
    my $self         = shift;
    my $return_value = $self->{ _db }->quote_timestamp( @_ );
    return python_deep_copy( $return_value );
}

sub prepare
{
    my $self = shift;
    return $self->{ _db }->prepare( @_ );
}

sub in_transaction
{
    my $self = shift;
    return $self->{ _db }->in_transaction( @_ );
}

sub show_error_statement
{
    my $self = shift;
    return $self->{ _db }->show_error_statement( @_ );
}

sub set_show_error_statement
{
    my $self = shift;
    return $self->{ _db }->set_show_error_statement( @_ );
}

sub print_warn
{
    my $self = shift;
    return $self->{ _db }->print_warn( @_ );
}

sub set_print_warn
{
    my $self = shift;
    return $self->{ _db }->set_print_warn( @_ );
}

sub copy_from
{
    my $self = shift;

    return $self->{ _db }->copy_from( @_ );
}

{

    package MediaWords::DB::HandlerProxy::CopyToProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    sub new
    {
        my ( $class, $python_result ) = @_;

        my $self = {};
        bless $self, $class;

        $self->{ _python_result } = $python_result;

        return $self;
    }

    sub get_line
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->get_line( @_ );
        return python_deep_copy( $return_value );
    }

    sub end
    {
        my $self = shift;
        return $self->{ _python_result }->end( @_ );
    }

    1;
}

sub copy_to
{
    my $self = shift;

    my $python_copy_to = $self->{ _db }->copy_to( @_ );
    return MediaWords::DB::HandlerProxy::CopyToProxy->new( $python_copy_to );
}

sub attach_child_query
{
    my $self = shift;

    my $return_value = $self->{ _db }->attach_child_query( @_ );
    return python_deep_copy( $return_value );
}

1;
