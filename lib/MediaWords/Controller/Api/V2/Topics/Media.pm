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
use MediaWords::CM::Dump;

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

sub list : Chained('media') : Args(0) : ActionClass('REST')
{

}

# if controversy_time_slices_id is specified, create a temporary
# table with the media name that supercedes the normal media table
# but includes only media in the given controversy time slice and
# has the controversy metric data
sub _create_controversy_media_table
{
    my ( $self, $c, $cdts_id ) = @_;

    # my $cdts_mode = $c->req->params->{ controversy_mode } || '';

    return unless ( $cdts_id );

    $self->{ controversy_media } = 1;

    # my $live = $cdts_mode eq 'live' ? 1 : 0;

    my $db = $c->dbis;

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $cdts_id )
      || die( "Unable to find controversy_dump_time_slice with id '$cdts_id'" );

    my $controversy = $db->query( <<END, $cdts->{ controversy_dumps_id } )->hash;
select * from controversies where controversies_id in (
    select controversies_id from controversy_dumps where controversy_dumps_id = ? )
END

    $db->begin;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, 0 );

    $db->query( <<END );
create temporary table media as
    select m.name, m.url, mlc.*
        from dump_media m join dump_medium_link_counts mlc on ( m.media_id = mlc.media_id )
END

    $db->commit;
}

sub list_GET : Local
{
    my ( $self, $c ) = @_;
    my $db   = $c->dbis;
    my $cdts = MediaWords::CM::get_time_slice_for_controversy(
        $c->dbis,
        $c->stash->{ topic_id },
        $c->req->params->{ timeslice },
        $c->req->params->{ snapshot }
    );
    my $entity = {};
    if ( $cdts )
    {
        $self->_create_controversy_media_table( $c, $cdts->{ controversy_dump_time_slices_id } );

        $entity->{ media } = $db->query( "select * from media order by inlink_count desc, media_id" )->hashes;

        $self->status_ok( $c, entity => $entity );
    }

}

1;
