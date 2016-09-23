package MediaWords::Controller::Api::V2::Topics::Permissions;
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

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => {
    user_list_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    list_GET => { Does => [ qw( ~TopicsAuthenticated ~Throttled ~Logged ) ] },
 } );

sub user_list : Chained( '/') : PathPart( 'api/v2/topics/permissions/user/list' ) : Args(0) : ActionClass( 'MC_REST')
{

}

sub user_list_GET : Local
{
    my ( $self, $c ) = @_;

    $self->status_ok( $c, entity => { user => 'list!' } );
}

sub apibase : Chained('/') : PathPart('api/v2/topics/') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;
    $c->stash->{ topics_id } = $topics_id;
}

sub list : Chained('apibase') :PathPart( 'permissions/list' ) : Args(0): ActionClass('MC_REST')
{

}

sub list_GET: Local
{
    my ( $self, $c ) = @_;

    $self->status_ok( $c, entity => { topic =>  'list!' } );

}

# sub media_list_GET : Local
# {
#     my ( $self, $c ) = @_;
#
#     my $timespan = MediaWords::TM::set_timespans_id_param( $c );
#
#     MediaWords::DBI::ApiLinks::process_and_stash_link( $c );
#
#     my $db = $c->dbis;
#
#     my $sort_param = $c->req->params->{ sort } || 'inlink';
#
#     # md5 hashing is to make tie breaks random but consistent
#     my $sort_clause =
#       ( $sort_param eq 'social' )
#       ? 'mlc.bitly_click_count desc nulls last, md5( m.media_id::text )'
#       : 'mlc.media_inlink_count desc, md5( m.media_id::text )';
#
#     my $timespans_id = $timespan->{ timespans_id };
#     my $snapshots_id = $timespan->{ snapshots_id };
#
#     my $limit  = $c->req->params->{ limit };
#     my $offset = $c->req->params->{ offset };
#
#     my $extra_clause = _get_extra_where_clause( $c, $timespans_id );
#
#     my $media = $db->query( <<SQL, $timespans_id, $snapshots_id, $limit, $offset )->hashes;
# select *
#     from snap.medium_link_counts mlc
#         join snap.media m on mlc.media_id = m.media_id
#     where mlc.timespans_id = \$1 and
#         m.snapshots_id = \$2
#         $extra_clause
#     order by $sort_clause
#     limit \$3 offset \$4
#
# SQL
#
#     my $entity = { media => $media };
#
#     MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'media' );
#
#     $self->status_ok( $c, entity => $entity );
# }

1;
