use strict;
use warnings;

# test MediaWords::DBI::DashboardMediaSets::get_colors

use Test::More tests => 18;
use Test::NoWarnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use MediaWords::Test::DB;
use MediaWords::DBI::DashboardMediaSets;

# create a stub dashboard_media_sets for testing
sub create_dashboard_media_sets
{
    my ( $db ) = @_;

    my $tag_set = $db->create( 'tag_sets', { name => 'test' } );
    my $tag = $db->create( 'tags', { tag => 'test', tag_sets_id => $tag_set->{ tag_sets_id } } );

    my $dashboard = $db->create( 'dashboards', { name => "test", start_date => '2010-01-01', end_date => '2020-01-01' } );

    my $dashboard_media_sets = [];
    for my $i ( 1 .. 4 )
    {
        my $media_set =
          $db->create( 'media_sets', { name => "test $i", set_type => 'collection', tags_id => $tag->{ tags_id } } );
        my $dashboard_media_set = $db->create(
            'dashboard_media_sets',
            {
                dashboards_id => $dashboard->{ dashboards_id },
                media_sets_id => $media_set->{ media_sets_id }
            }
        );
        push( @{ $dashboard_media_sets }, $dashboard_media_set );
    }

    return $dashboard_media_sets;
}

# make sure that get_colors generates consistent colors stored in the db
sub test_colors
{
    my ( $db, $dashboard_media_sets ) = @_;

    map { ok( !$_->{ color }, "dms color initially null" ) } @{ $dashboard_media_sets };

    my $colors_returned_map = {};
    for my $dms ( @{ $dashboard_media_sets } )
    {
        $dms->{ color_returned } = MediaWords::DBI::DashboardMediaSets::get_color( $db, $dms );
        ok( $dms->{ color_returned }, "dms color returned" );

        ok( !$colors_returned_map->{ $dms->{ color_returned } }, "colors are unique: $dms->{ color_returned }" );
        $colors_returned_map->{ $dms->{ color_returned } } = 1;
    }

    for my $dms ( @{ $dashboard_media_sets } )
    {
        my $new_dms = $db->find_by_id( 'dashboard_media_sets', $dms->{ dashboard_media_sets_id } );
        is( $dms->{ color_returned }, $new_dms->{ color }, "color returned is color in db" );
    }

}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;

            my $dashboard_media_sets = create_dashboard_media_sets( $db );
            test_colors( $db, $dashboard_media_sets );

            Test::NoWarnings::had_no_warnings();
        }
    );
}

main();
