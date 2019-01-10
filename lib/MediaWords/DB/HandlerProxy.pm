package MediaWords::DB::HandlerProxy;

# Proxy to DatabaseHandler Python implementation. Makes return values writable.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

# If Python passes method arguments as named parameters, e.g.:
#
#     db.create(table='foo', insert_hash={'a': 'b'}))
#
# first argument (after shifting $self) will be an empty arrayref:
#
#    @_ = [
#        [],
#        {
#            'table' => 'media',
#            'insert_hash' => {
#                'url' => 'http://media.test/A',
#                'name' => 'A'
#            }
#        }
#    ];
sub _python_named_parameters
{
    # Exactly two array parameters
    if ( scalar( @_ ) == 2 )
    {

        # First one is a list
        if ( ref( $_[ 0 ] ) eq ref( [] ) )
        {

            # ...which is empty
            if ( scalar( @{ $_[ 0 ] } ) == 0 )
            {

                # Second one is a hashref
                if ( ref( $_[ 1 ] ) eq ref( {} ) )
                {

                    # ...which is not empty
                    if ( scalar( keys( %{ $_[ 1 ] } ) ) > 0 )
                    {

                        return 1;
                    }
                }
            }
        }
    }

    return 0;
}

sub new($$)
{
    my ( $class, $db ) = @_;

    my $self = {};
    bless $self, $class;

    $self->{ _db } = $db;

    return $self;
}

sub disconnect($)
{
    my $self = shift;

    $self->{ _db }->disconnect();
    delete $self->{ _db };
}

sub dbh($)
{
    my $self = shift;
    return $self->{ _db }->dbh();
}

sub schema_is_up_to_date($)
{
    my $self = shift;
    return $self->{ _db }->schema_is_up_to_date();
}

{

    package MediaWords::DB::HandlerProxy::ResultProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    sub new($$)
    {
        my ( $class, $python_result ) = @_;

        my $self = {};
        bless $self, $class;

        $self->{ _python_result } = $python_result;

        return $self;
    }

    sub columns($)
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->columns();
        return $return_value if MediaWords::Util::Python::called_from_python();

        my $writable_value = python_deep_copy( $return_value );
        return wantarray ? @{ $writable_value } : $writable_value;
    }

    sub rows($)
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->rows();
        return $return_value if MediaWords::Util::Python::called_from_python();

        return python_deep_copy( $return_value );
    }

    sub array($)
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->array();
        return $return_value if MediaWords::Util::Python::called_from_python();

        return python_deep_copy( $return_value );
    }

    sub hash($)
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->hash();
        return $return_value if MediaWords::Util::Python::called_from_python();

        return python_deep_copy( $return_value );
    }

    sub flat($)
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->flat();
        return $return_value if MediaWords::Util::Python::called_from_python();

        my $writable_value = python_deep_copy( $return_value );
        return wantarray ? @{ $writable_value } : $writable_value;
    }

    sub hashes($)
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->hashes();
        return $return_value if MediaWords::Util::Python::called_from_python();

        my $writable_value = python_deep_copy( $return_value );
        return wantarray ? @{ $writable_value } : $writable_value;
    }

    sub text($;$)
    {
        my $self = shift;

        my $text_type;
        if ( MediaWords::DB::HandlerProxy::_python_named_parameters( @_ ) )
        {
            $text_type = $_[ 1 ]->{ 'text_type' };
        }
        else
        {
            ( $text_type ) = @_;
        }

        my $return_value = $self->{ _python_result }->text( $text_type );
        return $return_value if MediaWords::Util::Python::called_from_python();

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

sub primary_key_column($$)
{
    my $self = shift;

    my $table;
    if ( _python_named_parameters( @_ ) )
    {
        $table = $_[ 1 ]->{ 'table' };
    }
    else
    {
        ( $table ) = @_;
    }

    my $return_value = $self->{ _db }->primary_key_column( $table );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub find_by_id($$$)
{
    my $self = shift;

    my ( $table, $object_id );
    if ( _python_named_parameters( @_ ) )
    {
        $table     = $_[ 1 ]->{ 'table' };
        $object_id = $_[ 1 ]->{ 'object_id' };
    }
    else
    {
        ( $table, $object_id ) = @_;
    }

    my $return_value = $self->{ _db }->find_by_id( $table, $object_id );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub require_by_id($$$)
{
    my $self = shift;

    my ( $table, $object_id );
    if ( _python_named_parameters( @_ ) )
    {
        $table     = $_[ 1 ]->{ 'table' };
        $object_id = $_[ 1 ]->{ 'object_id' };
    }
    else
    {
        ( $table, $object_id ) = @_;
    }

    my $return_value = $self->{ _db }->require_by_id( $table, $object_id );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub select($$$;$)
{
    my $self = shift;

    my ( $table, $what_to_select, $condition_hash );
    if ( _python_named_parameters( @_ ) )
    {
        $table          = $_[ 1 ]->{ 'table' };
        $what_to_select = $_[ 1 ]->{ 'what_to_select' };
        $condition_hash = $_[ 1 ]->{ 'condition_hash' };
    }
    else
    {
        ( $table, $what_to_select, $condition_hash ) = @_;
    }

    my $python_result = $self->{ _db }->select( $table, $what_to_select, $condition_hash );
    return MediaWords::DB::HandlerProxy::ResultProxy->new( $python_result );
}

sub update_by_id($$$$)
{
    my $self = shift;

    my ( $table, $object_id, $update_hash );
    if ( _python_named_parameters( @_ ) )
    {
        $table       = $_[ 1 ]->{ 'table' };
        $object_id   = $_[ 1 ]->{ 'object_id' };
        $update_hash = $_[ 1 ]->{ 'update_hash' };
    }
    else
    {
        ( $table, $object_id, $update_hash ) = @_;
    }

    return $self->{ _db }->update_by_id( $table, $object_id, $update_hash );
}

sub delete_by_id($$$)
{
    my $self = shift;

    my ( $table, $object_id );
    if ( _python_named_parameters( @_ ) )
    {
        $table     = $_[ 1 ]->{ 'table' };
        $object_id = $_[ 1 ]->{ 'object_id' };
    }
    else
    {
        ( $table, $object_id ) = @_;
    }

    return $self->{ _db }->delete_by_id( $table, $object_id );
}

sub insert($$$)
{
    my $self = shift;

    my ( $table, $insert_hash );
    if ( _python_named_parameters( @_ ) )
    {
        $table       = $_[ 1 ]->{ 'table' };
        $insert_hash = $_[ 1 ]->{ 'insert_hash' };
    }
    else
    {
        ( $table, $insert_hash ) = @_;
    }

    my $return_value = $self->{ _db }->insert( $table, $insert_hash );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub create($$$)
{
    my $self = shift;

    my ( $table, $insert_hash );
    if ( _python_named_parameters( @_ ) )
    {
        $table       = $_[ 1 ]->{ 'table' };
        $insert_hash = $_[ 1 ]->{ 'insert_hash' };
    }
    else
    {
        ( $table, $insert_hash ) = @_;
    }

    my $return_value = $self->{ _db }->create( $table, $insert_hash );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub find_or_create($$$)
{
    my $self = shift;

    my ( $table, $insert_hash );
    if ( _python_named_parameters( @_ ) )
    {
        $table       = $_[ 1 ]->{ 'table' };
        $insert_hash = $_[ 1 ]->{ 'insert_hash' };
    }
    else
    {
        ( $table, $insert_hash ) = @_;
    }

    my $return_value = $self->{ _db }->find_or_create( $table, $insert_hash );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub query_paged_hashes($$$$)
{
    my $self = shift;

    my ( $query, $page, $rows_per_page );
    if ( _python_named_parameters( @_ ) )
    {
        $query         = $_[ 1 ]->{ 'query' };
        $page          = $_[ 1 ]->{ 'page' };
        $rows_per_page = $_[ 1 ]->{ 'rows_per_page' };
    }
    else
    {
        ( $query, $page, $rows_per_page ) = @_;
    }

    return $self->{ _db }->query_paged_hashes( $query, $page, $rows_per_page );
}

sub get_temporary_ids_table($$;$)
{
    my $self = shift;

    my ( $ids, $ordered );
    if ( _python_named_parameters( @_ ) )
    {
        $ids     = $_[ 1 ]->{ 'ids' };
        $ordered = $_[ 1 ]->{ 'ordered' };
    }
    else
    {
        ( $ids, $ordered ) = @_;
    }

    my $return_value = $self->{ _db }->get_temporary_ids_table( $ids, $ordered );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub begin($)
{
    my $self = shift;
    return $self->{ _db }->begin();
}

sub begin_work($)
{
    my $self = shift;
    return $self->{ _db }->begin_work();
}

sub commit($)
{
    my $self = shift;
    return $self->{ _db }->commit();
}

sub rollback($)
{
    my $self = shift;
    return $self->{ _db }->rollback();
}

sub quote($$)
{
    my $self = shift;

    my ( $value );
    if ( _python_named_parameters( @_ ) )
    {
        $value = $_[ 1 ]->{ 'value' };
    }
    else
    {
        ( $value ) = @_;
    }

    my $return_value = $self->{ _db }->quote( $value );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub quote_bool($$)
{
    my $self = shift;

    my ( $value );
    if ( _python_named_parameters( @_ ) )
    {
        $value = $_[ 1 ]->{ 'value' };
    }
    else
    {
        ( $value ) = @_;
    }

    my $return_value = $self->{ _db }->quote_bool( $value );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub quote_varchar($$)
{
    my $self = shift;

    my ( $value );
    if ( _python_named_parameters( @_ ) )
    {
        $value = $_[ 1 ]->{ 'value' };
    }
    else
    {
        ( $value ) = @_;
    }

    my $return_value = $self->{ _db }->quote_varchar( $value );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub quote_date($$)
{
    my $self = shift;

    my ( $value );
    if ( _python_named_parameters( @_ ) )
    {
        $value = $_[ 1 ]->{ 'value' };
    }
    else
    {
        ( $value ) = @_;
    }

    my $return_value = $self->{ _db }->quote_date( $value );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub quote_timestamp($$)
{
    my $self = shift;

    my ( $value );
    if ( _python_named_parameters( @_ ) )
    {
        $value = $_[ 1 ]->{ 'value' };
    }
    else
    {
        ( $value ) = @_;
    }

    my $return_value = $self->{ _db }->quote_timestamp( $value );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

sub prepare($$)
{
    my $self = shift;

    my ( $sql );
    if ( _python_named_parameters( @_ ) )
    {
        $sql = $_[ 1 ]->{ 'sql' };
    }
    else
    {
        ( $sql ) = @_;
    }

    return $self->{ _db }->prepare( $sql );
}

sub in_transaction($)
{
    my $self = shift;
    return $self->{ _db }->in_transaction();
}

sub show_error_statement($)
{
    my $self = shift;
    return $self->{ _db }->show_error_statement();
}

sub set_show_error_statement($$)
{
    my $self = shift;

    my ( $show_error_statement );
    if ( _python_named_parameters( @_ ) )
    {
        $show_error_statement = $_[ 1 ]->{ 'show_error_statement' };
    }
    else
    {
        ( $show_error_statement ) = @_;
    }

    return $self->{ _db }->set_show_error_statement( $show_error_statement );
}

sub print_warn($)
{
    my $self = shift;
    return $self->{ _db }->print_warn();
}

sub set_print_warn($$)
{
    my $self = shift;

    my ( $print_warn );
    if ( _python_named_parameters( @_ ) )
    {
        $print_warn = $_[ 1 ]->{ 'print_warn' };
    }
    else
    {
        ( $print_warn ) = @_;
    }

    return $self->{ _db }->set_print_warn( $print_warn );
}

sub copy_from($$)
{
    my $self = shift;

    my ( $sql );
    if ( _python_named_parameters( @_ ) )
    {
        $sql = $_[ 1 ]->{ 'sql' };
    }
    else
    {
        ( $sql ) = @_;
    }

    return $self->{ _db }->copy_from( $sql );
}

{

    package MediaWords::DB::HandlerProxy::CopyToProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    sub new($$)
    {
        my ( $class, $python_result ) = @_;

        my $self = {};
        bless $self, $class;

        $self->{ _python_result } = $python_result;

        return $self;
    }

    sub get_line($)
    {
        my $self         = shift;
        my $return_value = $self->{ _python_result }->get_line();
        return $return_value if MediaWords::Util::Python::called_from_python();

        return python_deep_copy( $return_value );
    }

    sub end($)
    {
        my $self = shift;
        return $self->{ _python_result }->end();
    }

    1;
}

sub copy_to($$)
{
    my $self = shift;

    my ( $sql );
    if ( _python_named_parameters( @_ ) )
    {
        $sql = $_[ 1 ]->{ 'sql' };
    }
    else
    {
        ( $sql ) = @_;
    }

    my $python_copy_to = $self->{ _db }->copy_to( $sql );
    return MediaWords::DB::HandlerProxy::CopyToProxy->new( $python_copy_to );
}

sub attach_child_query($$$$$;$)
{
    my $self = shift;

    my ( $data, $child_query, $child_field, $id_column, $single );
    if ( _python_named_parameters( @_ ) )
    {
        $data        = $_[ 1 ]->{ 'data' };
        $child_query = $_[ 1 ]->{ 'child_query' };
        $child_field = $_[ 1 ]->{ 'child_field' };
        $id_column   = $_[ 1 ]->{ 'id_column' };
        $single      = $_[ 1 ]->{ 'single' };
    }
    else
    {
        ( $data, $child_query, $child_field, $id_column, $single ) = @_;
    }

    my $return_value = $self->{ _db }->attach_child_query(
        $data,           #
        $child_query,    #
        $child_field,    #
        $id_column,      #
        $single          #
    );
    return $return_value if MediaWords::Util::Python::called_from_python();

    return python_deep_copy( $return_value );
}

1;
