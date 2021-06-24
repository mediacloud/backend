package MediaWords::DBI::Timespans;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;



sub _get_timespan
{
    my ( $db, $timespans_id ) = @_;

    # Could be optimized if we knew topics_id here
    my $timespan = $db->query( <<SQL, $timespans_id )->hash;
        SELECT *
        FROM timespans
        WHERE timespans_id = ?
SQL
    unless ( $timespan )
    {
        LOGDIE( "no timespan for timespan $timespans_id" );
    }
}

sub _get_overall_timespan_from_snapshot
{
    my ( $db, $snapshots_id ) = @_;

    my $timespan = $db->query( <<SQL,
        SELECT *
        FROM timespans
        WHERE
            snapshots_id = ? AND
            period = 'overall' AND
            foci_id IS NULL
SQL
        $snapshots_id
    )->hash;

    unless ( $timespan )
    {
        LOGDIE( "no overall timespan for snapshot $snapshots_id" );
    }
}

sub _get_latest_overall_timespan_from_topic
{
    my ( $db, $topics_id ) = @_;
    my $timespan = $db->query( <<SQL,
        SELECT timespans.*
        FROM timespans
            JOIN snapshots ON
                timespans.topics_id = snapshots.topics_id AND
                timespans.snapshots_id = timespans.snapshots_id
        where
            timespans.topics_id = ? AND
            timespans.period = 'overall' AND
            timespans.foci_id IS NULL
        ORDER BY snapshots.snapshot_date DESC
        LIMIT 1
SQL
        $topics_id
    )->hash;
}

# return in order of preference:
# * timespan if timespan specified
# * latest timespan of snapshot is specified
# * latest overall timespan
sub _get_timespan_for_topic($$$$)
{
    my ( $db, $topics_id, $timespans_id, $snapshots_id ) = @_;

    $timespans_id ||= '';
    $snapshots_id ||= '';

    TRACE "_get_timespan_for_topic: topics_id-$topics_id timespans_id-$timespans_id snapshots_id-$snapshots_id";

    my $timespan = $timespans_id && _get_timespan( $db, $timespans_id );

    return $timespan if ( $timespan );

    $timespan = $snapshots_id && _get_overall_timespan_from_snapshot( $db, $snapshots_id );

    return $timespan if ( $timespan );

    return _get_latest_overall_timespan_from_topic( $db, $topics_id );

    return $timespan;
}

# call a get_timespan_for_contoversy; die if no timespan can be found.
sub require_timespan_for_topic($$$$)
{
    my ( $db, $topics_id, $timespans_id, $snapshots_id ) = @_;

    my $timespan = _get_timespan_for_topic( $db, $topics_id, $timespans_id, $snapshots_id );

    die( "Unable to find timespan for topic, timespan, or snapshot" ) unless ( $timespan );

    return $timespan;
}

# given a topics api request, call require_timespan_for_topic using the request topics_id, timespans_id, and
# snapshots_id, set the timespans_id parameter, and return the timespan
sub set_timespans_id_param($)
{
    my ( $c ) = @_;

    my $timespan = require_timespan_for_topic(
        $c->dbis,
        $c->stash->{ topics_id },
        $c->req->params->{ timespans_id },
        $c->req->params->{ snapshots_id }
    );

    $c->req->params->{ topics_id } = $timespan->{ topics_id };
    $c->req->params->{ timespans_id } = $timespan->{ timespans_id };

    return $timespan;
}

1;
