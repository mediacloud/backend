use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 166;

use MediaWords::DB;

use_ok( 'MediaWords::Util::Colors' );

sub test_get_consistent_color
{
    my ( $db ) = @_;

    my $color_c_baz = MediaWords::Util::Colors::get_consistent_color( $db, 'c', 'baz' );
    my $color_b_baz = MediaWords::Util::Colors::get_consistent_color( $db, 'b', 'baz' );
    my $color_b_bar = MediaWords::Util::Colors::get_consistent_color( $db, 'b', 'bar' );
    my $color_a_baz = MediaWords::Util::Colors::get_consistent_color( $db, 'a', 'baz' );
    my $color_a_bar = MediaWords::Util::Colors::get_consistent_color( $db, 'a', 'bar' );
    my $color_a_foo = MediaWords::Util::Colors::get_consistent_color( $db, 'a', 'foo' );

    my ( $num_db_colors ) = $db->query( "select count(*) from color_sets" )->flat;

    is( $num_db_colors, 9, "number of colors" );

    ok( $color_a_foo ne $color_a_bar, "color_a_foo ne color_a_bar" );
    ok( $color_a_foo ne $color_a_baz, "color_a_foo ne color_a_baz" );
    ok( $color_a_bar ne $color_a_baz, "color_a_bar ne color_a_baz" );

    ok( $color_b_bar ne $color_b_baz, "color_b_bar ne color_b_baz" );

    my $color_a_foo_2 = MediaWords::Util::Colors::get_consistent_color( $db, 'a', 'foo' );
    my $color_a_bar_2 = MediaWords::Util::Colors::get_consistent_color( $db, 'a', 'bar' );
    my $color_a_baz_2 = MediaWords::Util::Colors::get_consistent_color( $db, 'a', 'baz' );
    my $color_b_bar_2 = MediaWords::Util::Colors::get_consistent_color( $db, 'b', 'bar' );
    my $color_b_baz_2 = MediaWords::Util::Colors::get_consistent_color( $db, 'b', 'baz' );
    my $color_c_baz_2 = MediaWords::Util::Colors::get_consistent_color( $db, 'c', 'baz' );

    is( $color_a_foo_2, $color_a_foo, 'color_a_foo is consistent' );
    is( $color_a_bar_2, $color_a_bar, 'color_a_bar is consistent' );
    is( $color_a_baz_2, $color_a_baz, 'color_a_baz is consistent' );
    is( $color_b_bar_2, $color_b_bar, 'color_a_bar is consistent' );
    is( $color_b_baz_2, $color_b_baz, 'color_a_baz is consistent' );
    is( $color_c_baz_2, $color_c_baz, 'color_a_baz is consistent' );
}

sub test_get_consistent_color_partisan
{
    my ( $db ) = @_;

    my $partisan_colors = {
        partisan_2012_conservative => 'c10032',
        partisan_2012_liberal      => '00519b',
        partisan_2012_libertarian  => '009543'
    };

    while ( my ( $id, $color ) = each( %{ $partisan_colors } ) )
    {
        my $got_color = MediaWords::Util::Colors::get_consistent_color( $db, 'partisan_code', $id );
        is( $got_color, $color, "color for partisan id '$id'" );
    }
}

sub test_get_consistent_color_create($)
{
    my ( $db ) = @_;

    my $set = 'test_set';

    my $unique_color_mapping = {};

    # Test if helper is able to create new colors when it runs out of hardcoded set
    for ( my $x = 0 ; $x < 50 ; ++$x )
    {
        my $id = "color-$x";
        my $color = MediaWords::Util::Colors::get_consistent_color( $db, $set, $id );
        is( length( $color ), length( 'ffffff' ) );
        $unique_color_mapping->{ $id } = $color;
    }

    # Make sure that if we run it again, we'll get the same colors
    for ( my $x = 0 ; $x < 50 ; ++$x )
    {
        my $id = "color-$x";
        my $color = MediaWords::Util::Colors::get_consistent_color( $db, $set, $id );
        is( length( $color ),               length( 'ffffff' ) );
        is( $unique_color_mapping->{ $id }, $color );
    }
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_get_consistent_color( $db );
    test_get_consistent_color_partisan( $db );
    test_get_consistent_color_create( $db );
}

main();
