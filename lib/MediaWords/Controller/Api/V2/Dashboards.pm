package MediaWords::Controller::Api::V2::Dashboards;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;
use MediaWords::Controller::Api::V2::MC_REST_SimpleObject;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

sub get_table_name
{
    return "dashboards";
}

sub has_nested_data
{
    return 1;
}

sub default_output_fields
{
    return [ qw ( name dashboards_id ) ];
}

sub _add_nested_data
{

    my ( $self, $db, $dashboards ) = @_;

    foreach my $dashboard ( @{ $dashboards } )
    {
        my $media_sets = $db->query(
            "select ms.media_sets_id, ms.name from media_sets ms, dashboard_media_sets dms where  " .
              " dms.media_sets_id=ms.media_sets_id and dms.dashboards_id  = ? ORDER by ms.media_sets_id",
            $dashboard->{ dashboards_id }
        )->hashes;

        foreach my $media_set ( @$media_sets )
        {
            my $media = $db->query(
                "SELECT m.name, m.url, m.media_id from media m , media_sets_media_map msmm" .
                  " WHERE m.media_id = msmm.media_id AND msmm.media_sets_id = ? ORDER BY m.media_id ",
                $media_set->{ media_sets_id }
            )->hashes();
            $media_set->{ media } = $media;
        }

        $dashboard->{ media_sets } = $media_sets;
    }

    return $dashboards;

}

1;
