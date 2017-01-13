# Wrapper around COPY TO
package MediaWords::DB::Handler::CopyTo;

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

sub get_line($)
{
    my ( $self ) = @_;

    my $line = '';
    if ( $self->{ _mediawords_db }->{ _db }->dbh->pg_getcopydata( $line ) > -1 )
    {
        return $line;
    }
    else
    {
        return undef;
    }
}

1;
