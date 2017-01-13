# Wrapper around query result
#
# Clarifies which DBIx::Simple helpers are being used and need to be ported
# to Python)
package MediaWords::DB::Handler::Result;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;

sub new
{
    my $class      = shift;
    my $db         = shift;
    my @query_args = @_;

    if ( ref( $db ) ne 'MediaWords::DB::Handler' )
    {
        die "Database is not a reference to MediaWords::DB::Handler but rather to " . ref( $db );
    }

    if ( scalar( @query_args ) == 0 )
    {
        die 'No query or its parameters.';
    }
    unless ( $query_args[ 0 ] )
    {
        die 'Query is empty or undefined.';
    }

    my $self = {};
    bless $self, $class;

    eval { $self->{ result } = $db->_query_internal( @query_args ); };
    if ( $@ )
    {
        die "Query error: $@";
    }

    return $self;
}

#
# MediaWords::DB::Handler::Result methods
#

# Returns a list of column names
sub columns($)
{
    my $self = shift;
    return $self->{ result }->columns;
}

# Returns the number of rows affected by the last row affecting command,
# or -1 if the number of rows is not known or not available
sub rows($)
{
    my $self = shift;
    return $self->{ result }->rows;
}

# bind(LIST) -- not used
# attr(...) -- not used
# func(...) -- not used
# finish -- not used

#
# Fetching a single row at a time
#

# Returns a reference to an array
sub array($)
{
    my $self = shift;
    return $self->{ result }->array;
}

# Returns a reference to a hash, keyed by column name
sub hash($)
{
    my $self = shift;
    return $self->{ result }->hash;
}

# fetch -- not used
# into(LIST) -- not used
# kv_list -- not used
# kv_array -- not used

#
# Fetching all remaining rows
#

# Returns a flattened list
sub flat($)
{
    my $self = shift;
    return $self->{ result }->flat;
}

# Returns a list of references to hashes, keyed by column name
sub hashes($)
{
    my $self = shift;
    return $self->{ result }->hashes;
}

# Returns a string with a simple text representation of the data. $type can
# be any of: neat, table, box. It defaults to table if Text::Table is
# installed, to neat if it isn't
sub text($$)
{
    my ( $self, $type ) = @_;
    return $self->{ result }->text( $type );
}

# arrays -- not used
# kv_flat -- not used
# kv_arrays -- not used
# objects($class, ...) -- not used
# map_arrays($column_number) -- not used
# map_hashes($column_name) -- not used
# map -- not used
# xto(%attr) -- not used
# html(%attr) -- not used

1;
