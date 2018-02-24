use strict;
use warnings;

use Inline::Python;
use Test::Deep;
use Test::More tests => 2;

use MediaWords::CommonLibs;

use MediaWords::Test::DB;
use MediaWords::Test::DB::HandlerProxy;

# test whether calling hashes() or flat() returns a single row list or just the single value.
sub test_single_row_list($)
{
    my ( $db ) = @_;

    my $hashes = MediaWords::Test::DB::HandlerProxy::get_single_row_hashes( $db );

    is( ref( $hashes ), ref( [] ), "hashes single row return type" );

    my $r = $db->query( "select 'foo' as foo" )->hashes();

    $r->[ 0 ]->{ foo } = 'bar';
    is( $r->[ 0 ]->{ foo }, 'bar', 'hashes results writeable' );

}

sub test_database($)
{
    my ( $db ) = @_;

    test_single_row_list( $db );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database( \&test_database );
}

main();
