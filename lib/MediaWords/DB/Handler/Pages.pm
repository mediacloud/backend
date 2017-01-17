# Wrapper around paged hashes
package MediaWords::DB::Handler::Pages;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Pages;

sub new
{
    my $class = shift;
    my ( $db, $query, $page, $rows_per_page ) = @_;

    my $self = {};
    bless $self, $class;

    if ( ref( $db ) ne 'MediaWords::DB::Handler' )
    {
        die "Database is not a reference to MediaWords::DB::Handler but rather to " . ref( $db );
    }

    if ( $page < 1 )
    {
        die 'Page must be 1 or bigger.';
    }

    my $offset = ( $page - 1 ) * $rows_per_page;

    $query .= " limit ( $rows_per_page + 1 ) offset $offset";

    my $rs = $db->query( $query );

    my $list = [];
    my $i    = 0;
    my $hash;
    while ( ( $hash = $rs->hash ) && ( $i++ < $rows_per_page ) )
    {
        push( @{ $list }, $hash );
    }

    my $max = $offset + $i;
    if ( $hash )
    {
        $max++;
    }

    my $pager = MediaWords::Util::Pages->new( $max, $rows_per_page, $page );

    $self->{ _list }  = $list;
    $self->{ _pager } = $pager;

    return $self;
}

sub list
{
    my $self = shift;
    return $self->{ _list };
}

sub pager
{
    my $self = shift;
    return $self->{ _pager };
}

1;
