# Wrapper around prepared statement
package MediaWords::DB::Handler::Statement;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use DBD::Pg qw(:pg_types);

our $VALUE_BYTEA = 1;

# There are other types (e.g. PG_POINT), but they aren't used currently by
# any live code

sub new($$$)
{
    my ( $class, $db, $sql ) = @_;

    my $self = {};
    bless $self, $class;

    if ( ref( $db ) ne 'MediaWords::DB::Handler' )
    {
        die "Database is not a reference to MediaWords::DB::Handler but rather to " . ref( $db );
    }

    $self->{ sql } = $sql;

    eval { $self->{ sth } = $db->{ _db }->dbh->prepare( $sql ); };
    if ( $@ )
    {
        die "Error while preparing statement '$sql': $@";
    }

    return $self;
}

sub bind_param($$$;$)
{
    my ( $self, $param_num, $bind_value, $bind_type ) = @_;

    if ( $param_num < 1 )
    {
        die "Parameter number must be >= 1.";
    }

    my $bind_args = undef;
    if ( defined $bind_type )
    {
        if ( $bind_type == $VALUE_BYTEA )
        {
            $bind_args = { pg_type => DBD::Pg::PG_BYTEA };
        }
        else
        {
            die "Unknown bind type $bind_type.";
        }
    }

    eval { $self->{ sth }->bind_param( $param_num, $bind_value, $bind_args ); };
    if ( $@ )
    {
        die "Error while binding parameter $param_num for prepared statement '" . $self->{ sql } . "': $@";
    }
}

sub execute($)
{
    my ( $self ) = @_;

    eval { $self->{ sth }->execute(); };
    if ( $@ )
    {
        die "Error while executing prepared statement '" . $self->{ sql } . "': $@";
    }
}

1;
