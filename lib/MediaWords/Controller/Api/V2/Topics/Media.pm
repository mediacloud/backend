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

__PACKAGE__->config( action => { media_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topic_id ) = @_;
    $c->stash->{ topic_id } = $topic_id;
}

# /topics/*/media/list
sub media_list : Chained('apibase') : PathPart('media/list') : Args(0) : ActionClass('MC_REST')
{

}

sub media_list_GET : Local
{
    my ( $self, $c ) = @_;
    my $entity = {};
    if ( $self->_create_controversy_media_table( $c ) )
    {
        my $db = $c->dbis;
        $entity->{ media } = $db->query( "select * from media order by inlink_count desc, media_id" )->hashes;
        $self->status_ok( $c, entity => $entity );
    }
    else
    {

    }
}

# /topics/*/media/*
sub media_id : Chained('apibase') : PathPart('media') : Args(1) : ActionClass('MC_REST')
{

}

sub media_id_GET : Local
{
    my ( $self, $c, $item ) = @_;
    my $entity = {};
    if ( $self->_create_controversy_media_table( $c ) )
    {
        my $db = $c->dbis;
        $entity->{ media }  = $db->query( "select * from media where media_id = \$1", $item )->hash;
        $entity->{ frames } = [];
        $entity->{ tags }   = $db->query( <<END, $c->stash->{ topic_id }, $item )->hashes;
  select distinct on (t.tags_id) t.tags_id, t.tag, t.tag_sets_id, t.label, t.description
  from cd.media_tags_map mmp join cd.tags t on t.tags_id = mmp.tags_id where
  mmp.controversy_dumps_id = \$1 and mmp.media_id=\$2
END
        $self->status_ok( $c, entity => $entity );
    }
    else
    {

    }

}

sub media : Chained('apibase') : PathPart('media') : CaptureArgs(1)
{
    my ( $self, $c, $story_id ) = @_;
    $c->stash->{ story_id } = $story_id;
}

sub media_GET : Local
{

}

# /topics/*/media/*/stories/list
sub media_stories_list : Chained('media') : PathPart('stories/list') : Args(0) : ActionClass('MC_REST')
{

}

sub media_stories_list_GET : Local
{
    my ( $self, $c ) = @_;
    my $entity = {};
    $self->status_ok( $c, entity => $entity );
}

# /topics/*/media/*/inlinks
sub media_inlinks : Chained('media') : PathPart('inlinks') : Args(0) : ActionClass('MC_REST')
{

}

sub media_inlinks_GET : Local
{
    my ( $self, $c ) = @_;
    my $entity = {};
    $self->status_ok( $c, entity => $entity );
}

# /topics/*/media/*/outlinks
sub media_outlinks : Chained('media') : PathPart('outlinks') : Args(0) : ActionClass('MC_REST')
{

}

sub media_outlinks_GET : Local
{
    my ( $self, $c ) = @_;
    my $entity = {};
    $self->status_ok( $c, entity => $entity );
}

# if controversy_time_slices_id is specified, create a temporary
# table with the media name that supercedes the normal media table
# but includes only media in the given controversy time slice and
# has the controversy metric data
sub _create_controversy_media_table
{
    my ( $self, $c ) = @_;
    my $cdts = MediaWords::CM::get_time_slice_for_controversy(
        $c->dbis,
        $c->stash->{ topic_id },
        $c->req->params->{ timeslice },
        $c->req->params->{ snapshot }
    );

    my $cdts_id = $cdts->{ controversy_dump_time_slices_id };

    return unless ( $cdts_id );

    $self->{ controversy_media } = 1;

    # my $live = $cdts_mode eq 'live' ? 1 : 0;

    my $db = $c->dbis;

    #  my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $cdts_id )
    #      || die( "Unable to find controversy_dump_time_slice with id '$cdts_id'" );

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

    return 1;
}

sub _prepare_media_for_controversy
{

}

1;
