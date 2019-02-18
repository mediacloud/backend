use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;
use Test::Deep;

use MediaWords::Test::API;

sub test_is_syndicated_ap($)
{
    my ( $db ) = @_;

    my $label = "stories/is_syndicated_ap";

    my $r = test_put( '/api/v2/util/is_syndicated_ap', { content => 'foo' } );
    is( $r->{ is_syndicated }, 0, "$label: not syndicated" );

    $r = test_put( '/api/v2/util/is_syndicated_ap', { content => '(ap)' } );
    is( $r->{ is_syndicated }, 1, "$label: syndicated" );

}

sub test_util($)
{
    my ( $db ) = @_;

    MediaWords::Test::API::setup_test_api_key( $db );

    test_is_syndicated_ap( $db );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_util( $db );

    done_testing();
}

main();
