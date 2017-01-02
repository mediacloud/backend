package MediaWords::Controller::Api::V2::Topics;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use HTTP::Status qw(:constants);

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    action => {
        list   => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        single => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub list : Local : ActionClass('MC_REST')
{
}

sub list_GET
{
    my ( $self, $c ) = @_;

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    my $name = $c->req->params->{ name } || '';

    my $limit  = $c->req->params->{ limit };
    my $offset = $c->req->params->{ offset };

    my $auth_users_id = $c->stash->{ api_auth }->{ auth_users_id };

    my $topics = $db->query( <<END, $auth_users_id, $name, $limit, $offset )->hashes;
select t.*, min( p.auth_users_id ) auth_users_id, min( p.user_permission ) user_permission
    from topics  t
        join topics_with_user_permission p using ( topics_id )
        left join snapshots snap on ( t.topics_id = snap.topics_id )
    where
        p.auth_users_id= \$1 and
        t.name like '%' || \$2 || '%'
    group by t.topics_id
    order by t.state = 'ready', t.state,  max( coalesce( snap.snapshot_date, '2000-01-01'::date ) ) desc
    limit \$3 offset \$4
END

    my $entity = { topics => $topics };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'topics' );

    $self->status_ok( $c, entity => $entity );
}

sub single : Local : ActionClass('MC_REST')
{
}

sub single_GET
{
    my ( $self, $c, $topics_id ) = @_;

    my $auth_users_id = $c->stash->{ api_auth }->{ auth_users_id };

    my $db = $c->dbis;

    my $topic = $db->query( <<SQL, $topics_id, $auth_users_id )->hash;
select * from topics_with_user_permission where topics_id = \$1 and auth_users_id = \$2
SQL

    if ( !$topic )
    {
        $c->response->status( HTTP_BAD_REQUEST );
        die( "Unknown topic '$topics_id'" );
    }

    $self->status_ok( $c, entity => { topics => [ $topic ] } );
}

1;
