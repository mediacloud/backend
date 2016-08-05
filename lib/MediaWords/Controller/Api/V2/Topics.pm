package MediaWords::Controller::Api::V2::Topics;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list_GET => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub list : Local : ActionClass('MC_REST')
{
}

sub list_GET : Local
{
    my ( $self, $c ) = @_;

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    my $limit  = $c->req->params->{ limit };
    my $offset = $c->req->params->{ offset };

    my $topics = $db->query( <<END, $limit, $offset )->hashes;
select c.*
    from topics c
        left join snapshots snap on ( c.topics_id = snap.topics_id )
    group by c.topics_id
    order by c.state = 'ready', c.state,  max( coalesce( snap.snapshot_date, '2000-01-01'::date ) ) desc
    limit \$1 offset \$2
END

    my $entity = { topics => $topics };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'topics' );

    $self->status_ok( $c, entity => $entity );
}

sub single : Local : ActionClass('MC_REST')
{
}

sub single_GET : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', $topics_id );

    $self->status_ok( $c, entity => { topics => [ $topic ] } );
}

1;
