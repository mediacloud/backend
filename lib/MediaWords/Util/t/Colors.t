use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 16;

use MediaWords::Test::DB;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::Colors' );
}

sub test_consistent_colors
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

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;
            test_consistent_colors( $db );
        }
    );
}

main();
