# Wrapper around COPY FROM
package MediaWords::DB::Handler::CopyFrom;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub new($$$)
{
    my ( $class, $db, $sql ) = @_;

    my $self = {};
    bless $self, $class;

    if ( ref( $db ) ne 'MediaWords::DB::Handler' )
    {
        die "Database is not a reference to MediaWords::DB::Handler but rather to " . ref( $db );
    }

    $self->{ _mediawords_db } = $db;

    eval { $self->{ _mediawords_db }->{ _db }->dbh->do( $sql ) };
    if ( $@ )
    {
        die "Error while running '$sql': $@";
    }

    return $self;
}

sub put_line($$)
{
    my ( $self, $line ) = @_;

    chomp $line;

    eval { $self->{ _mediawords_db }->{ _db }->dbh->pg_putcopydata( "$line\n" ); };
    if ( $@ )
    {
        die "Error on pg_putcopydata('$line'): $@";
    }
}

sub end($$)
{
    my ( $self ) = @_;

    eval { $self->{ _mediawords_db }->{ _db }->dbh->pg_putcopyend(); };
    if ( $@ )
    {
        die "Error on pg_putcopyend(): $@";
    }
}

1;
