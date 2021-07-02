package MediaWords::Controller::Api::V2::Topics::Timespans;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;

    $topics_id = int( $topics_id // 0 );
    unless ( $topics_id )
    {
        die "topics_id is unset.";
    }

    $c->stash->{ topics_id } = $topics_id;
}

sub timespans : Chained('apibase') : PathPart('timespans') : CaptureArgs(0)
{

}

sub list : Chained('timespans') : Args(0) : ActionClass('MC_REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id = int( $c->stash->{ topics_id } // 0 );

    my $snapshots_id = int( $c->req->params->{ snapshots_id } // 0 );
    my $foci_id      = int( $c->req->params->{ foci_id }      // 0 );
    my $timespans_id = int( $c->req->params->{ timespans_id } // 0 );

    my $snapshot = $db->require_by_id( 'snapshots', $snapshots_id ) if ( $snapshots_id );
    my $focus    = $db->require_by_id( 'foci',      $foci_id )      if ( $foci_id );
    my $timespan = $db->require_by_id( 'timespans', $timespans_id ) if ( $timespans_id );

    if ( !$snapshot && !$timespan )
    {
        $snapshot = $db->query( <<SQL,
            SELECT *
            FROM snapshots
            WHERE
                topics_id = \$1 AND
                state = 'completed'
            ORDER BY snapshot_date DESC
            LIMIT 1
SQL
            $topics_id
        )->hash;
        die( "Unable to find valid spanshot" ) unless ( $snapshot );
    }

    my $snapshot_clause = $snapshot ? "AND snapshots_id = $snapshot->{ snapshots_id }" : "";
    my $focus_clause    = $focus    ? "AND foci_id = $focus->{ foci_id }"              : "AND foci_id IS NULL";
    my $timespan_clause = $timespan ? "AND timespans_id = $timespan->{ timespans_id }" : "";

    my $timespans = $db->query( <<SQL,
        SELECT
            timespans_id,
            period,
            start_date,
            end_date,
            story_count,
            story_link_count,
            medium_count,
            medium_link_count,
            model_r2_mean,
            model_r2_stddev,
            model_num_media,
            foci_id,
            snapshots_id
        FROM timespans AS t
        where
            topics_id = ? AND
            $snapshot_clause
            $focus_clause
            $timespan_clause
        ORDER BY
            period,
            start_date,
            end_date
SQL
        $topics_id
    )->hashes;

    $self->status_ok( $c, entity => { timespans => $timespans } );
}

1;
