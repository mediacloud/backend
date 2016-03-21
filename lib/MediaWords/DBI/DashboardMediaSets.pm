package MediaWords::DBI::DashboardMediaSets;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Colors;

use strict;

# get a consistent color for a media set by either reading it from the
# color field of the dashboard media set or, if null, assigning a
# set of unique colors to each collection type dashboard media set in a dashboard
sub get_color
{
    my ( $db, $dashboard_media_set ) = @_;

    return $dashboard_media_set->{ color } if ( $dashboard_media_set->{ color } );

    my $all_dashboard_media_sets = $db->query(
        "select dms.* from dashboard_media_sets dms, media_sets ms " .
          "  where ms.media_sets_id = dms.media_sets_id and ms.set_type = 'collection' " . "    and dms.dashboards_id = ?",
        $dashboard_media_set->{ dashboards_id }
    )->hashes;

    my $return_color;

    my $num_colors = @{ $all_dashboard_media_sets };

    my $all_colors_hash = {};
    map { $all_colors_hash->{ $_ } = 1 } MediaWords::Util::Colors::get_colors( $num_colors );

    my $colorless_dashboard_media_sets = [];
    for my $dms ( @{ $all_dashboard_media_sets } )
    {
        if ( $dms->{ color } )
        {
            delete( $all_colors_hash->{ $dms->{ color } } );
            $return_color = $dms->{ color }
              if ( $dms->{ dashboard_media_sets_id } = $dashboard_media_set->{ dashboard_media_sets_id } );
        }
        else
        {
            push( @{ $colorless_dashboard_media_sets }, $dms );
        }
    }

    my $unassigned_colors = [ keys( %{ $all_colors_hash } ) ];

    for my $dms ( @{ $colorless_dashboard_media_sets } )
    {
        $dms->{ color } = pop( @{ $unassigned_colors } );

        $db->query(
            "update dashboard_media_sets set color = ? where dashboard_media_sets_id = ?",
            $dms->{ color },
            $dms->{ dashboard_media_sets_id }
        );

        $return_color = $dms->{ color }
          if ( $dms->{ dashboard_media_sets_id } == $dashboard_media_set->{ dashboard_media_sets_id } );
    }

    return $return_color;
}

1;
