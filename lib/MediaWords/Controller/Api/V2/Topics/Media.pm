package MediaWords::Controller::Api::V2::Topics::Media;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;
use MediaWords::Solr;
use MediaWords::TM::Snapshot;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topic_id ) = @_;
    $c->stash->{ topic_id } = $topic_id;
}

sub media : Chained('apibase') : PathPart('media') : CaptureArgs(0)
{

}

sub list : Chained('media') : Args(0) : ActionClass('MC_REST')
{

}

# if topic_timespans_id is specified, create a temporary
# table with the media name that supercedes the normal media table
# but includes only media in the given topic timespan and
# has the topic metric data
sub _create_topic_media_table
{
    my ( $self, $c, $timespans_id ) = @_;

    # my $timespan_mode = $c->req->params->{ topic_mode } || '';

    return unless ( $timespans_id );

    $self->{ topic_media } = 1;

    # my $live = $timespan_mode eq 'live' ? 1 : 0;

    my $db = $c->dbis;

    my $timespan = $db->find_by_id( 'timespans', $timespans_id )
      || die( "Unable to find timespan with id '$timespans_id'" );

    my $topic = $db->query( <<END, $timespan->{ snapshots_id } )->hash;
select * from topics where topics_id in (
    select topics_id from snapshots where snapshots_id = ? )
END

    $db->begin;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, 0 );

    $db->query( <<END );
create temporary table media as
    select m.name, m.url, mlc.*
        from snapshot_media m join snapshot_medium_link_counts mlc on ( m.media_id = mlc.media_id )
END

    $db->commit;
}

sub list_GET : Local
{
    my ( $self, $c ) = @_;

    my $db       = $c->dbis;
    my $timespan = MediaWords::TM::require_timespan_for_topic(
        $c->dbis,
        $c->stash->{ topic_id },
        $c->req->params->{ timespan },
        $c->req->params->{ snapshot }
    );

    my $sort_param = $c->req->params->{ sort } || 'inlink';

    # md5 hashing is to make tie breaks random but consistent
    my $sort_clause =
      ( $sort_param eq 'social' )
      ? 'mlc.bitly_click_count desc nulls last, md5( m.media_id::text )'
      : 'mlc.inlink_count desc, md5( m.media_id::text )';

    my $timespans_id = $timespan->{ timespans_id };
    my $snap_id      = $timespan->{ snapshots_id };

    my ( $media, $continuation_id ) = $self->do_continuation_query( $c, <<SQL, [ $timespans_id, $snap_id ] );
select *
    from snap.medium_link_counts mlc
        join snap.media m on mlc.media_id = m.media_id
    where mlc.timespans_id = \$1 and
        m.snapshots_id = \$2
    order by $sort_clause
SQL

    my $entity = { media => $media, timespan => $timespan, continuation_id => $continuation_id };

    $self->status_ok( $c, entity => $entity );
}

1;
