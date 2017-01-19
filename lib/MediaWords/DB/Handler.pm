package MediaWords::DB::Handler;

# Proxy to DatabaseHandler Python implementation. Makes return values writable.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

use MediaWords::Util::Config;
use Inline Python => MediaWords::Util::Config::get_mc_python_dir() . '/mediawords/db/handler.py';

sub new
{
    my $class = shift;

    my $self = {};
    bless $self, $class;

    $self->{ _db } = MediaWords::DB::Handler::DatabaseHandler->new( @_ );

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

sub query
{
    my $self = shift;
    return $self->{ _db }->query( @_ );
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
    my $self = shift;
    return $self->{ _db }->primary_key_column( @_ );
}

sub find_by_id
{
    my $self = shift;
    return $self->{ _db }->find_by_id( @_ );
}

sub require_by_id
{
    my $self = shift;
    return $self->{ _db }->require_by_id( @_ );
}

sub select
{
    my $self = shift;
    return $self->{ _db }->select( @_ );
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
    my $self = shift;
    return $self->{ _db }->insert( @_ );
}

sub create
{
    my $self = shift;
    return $self->{ _db }->create( @_ );
}

sub find_or_create
{
    my $self = shift;
    return $self->{ _db }->find_or_create( @_ );
}

sub query_paged_hashes
{
    my $self = shift;
    return $self->{ _db }->query_paged_hashes( @_ );
}

sub get_temporary_ids_table
{
    my $self = shift;
    return $self->{ _db }->get_temporary_ids_table( @_ );
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
    my $self = shift;
    return $self->{ _db }->quote( @_ );
}

sub quote_bool
{
    my $self = shift;
    return $self->{ _db }->quote_bool( @_ );
}

sub quote_varchar
{
    my $self = shift;
    return $self->{ _db }->quote_varchar( @_ );
}

sub quote_date
{
    my $self = shift;
    return $self->{ _db }->quote_date( @_ );
}

sub quote_timestamp
{
    my $self = shift;
    return $self->{ _db }->quote_timestamp( @_ );
}

sub prepare
{
    my $self = shift;
    return $self->{ _db }->prepare( @_ );
}

sub autocommit
{
    my $self = shift;
    return $self->{ _db }->autocommit( @_ );
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

sub prepare_on_server_side
{
    my $self = shift;
    return $self->{ _db }->prepare_on_server_side( @_ );
}

sub set_prepare_on_server_side
{
    my $self = shift;
    return $self->{ _db }->set_prepare_on_server_side( @_ );
}

sub copy_from
{
    my $self = shift;
    return $self->{ _db }->copy_from( @_ );
}

sub copy_to
{
    my $self = shift;
    return $self->{ _db }->copy_to( @_ );
}

sub attach_child_query
{
    my $self = shift;
    return $self->{ _db }->attach_child_query( @_ );
}

1;
