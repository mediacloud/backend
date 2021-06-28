package MediaWords::Controller::Api::V2::Users;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use MediaWords::Controller::Api::V2::MC_Controller_REST;

use Moose;
use namespace::autoclean;

use Readonly;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    action => {
        delete     => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        update     => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        list       => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        single     => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        list_roles => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub _update_roles($$$)
{
    my ( $db, $user, $roles ) = @_;

    return unless $roles;

    $roles = ref( $roles ) ? $roles : [ $roles ];

    $db->query( <<SQL, $user->{ auth_users_id }, $roles );
        DELETE FROM auth_users_roles_map
            USING auth_roles
        WHERE
            auth_users_roles_map.auth_roles_id = auth_roles.auth_roles_id AND
            auth_users_roles_map.auth_users_id = \$1 AND
            NOT (auth_roles.role = ANY(\$2 ))
SQL

    $db->query( <<SQL,
        INSERT INTO auth_users_roles_map (
            auth_users_id,
            auth_roles_id
        )
            SELECT
                \$1,
                auth_roles.auth_roles_id
            FROM auth_roles
            WHERE auth_roles.role = ANY( \$2 )
        ON CONFLICT (auth_users_id, auth_roles_id) DO NOTHING
SQL
        $user->{ auth_users_id }, $roles
    );

}

sub update : Local : ActionClass('MC_REST')
{
}

sub update_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/auth_users_id/ ] );

    my $user = $c->dbis->require_by_id( 'auth_users', $data->{ auth_users_id } );

    my $update_fields = [ qw/email full_name notes active has_consented/ ];

    my $input = { map { $_ => $data->{ $_ } } grep { exists( $data->{ $_ } ) } @{ $update_fields } };

    for my $field ( 'active', 'has_consented' )
    {
        if ( defined( $input->{ $field } ) )
        {
            $input->{ $field } = normalize_boolean_for_db( $input->{ $field } );
        }
    }

    my $db = $c->dbis;

    $db->update_by_id( 'auth_users', $data->{ auth_users_id }, $input ) if ( scalar( keys( %{ $input } ) ) );

    if ( exists( $data->{ weekly_requests_limit } ) )
    {
        $db->query(
            "UPDATE auth_user_limits SET weekly_requests_limit = ? WHERE auth_users_id = ?",
            $data->{ weekly_requests_limit },
            $data->{ auth_users_id }
        );
    }

    if ( exists( $data->{ max_topic_stories } ) ) {
        $db->query(
            "UPDATE auth_user_limits SET max_topic_stories = ? WHERE auth_users_id = ?",
            $data->{ max_topic_stories },
            $data->{ auth_users_id }
        );
    }

    _update_roles( $db, $user, $data->{ roles } );

    return $self->status_ok( $c, entity => { success => 1 } );
}

# query users for users/list or users/single
sub _get_users_list($$)
{
    my ( $db, $params ) = @_;

    my $users_ids = $params->{ auth_users_id };
    my $search    = $params->{ search };

    my $limit  = $params->{ limit };
    my $offset = $params->{ offset };

    my $id_clause = '1=1';
    if ( $users_ids )
    {
        $users_ids = ref( $users_ids ) ? $users_ids : [ $users_ids ];
        my $users_ids_list = join( ',', map { int( $_ ) } @{ $users_ids } );
        $id_clause = "auth_users_id IN ($users_ids_list)";
    }

    my $search_clause = '1=1';
    if ( $search )
    {
        my $q_search = $db->quote( $search );
        $search_clause = "( full_name ILIKE '%'||$q_search||'%' OR email ILIKE '%'||$q_search||'%' )";
    }

    my $users = $db->query( <<SQL,
        SELECT
            auth_users_id,
            email,
            full_name,
            notes,
            active,
            created_date,
            max_topic_stories,
            weekly_requests_limit,
            has_consented
        FROM auth_users au
            INNER JOIN auth_user_limits AS aul USING (auth_users_id)
        WHERE
            $id_clause AND
            $search_clause
        LIMIT \$1
        OFFSET \$2
SQL
        $limit, $offset
    )->hashes();

    $users = $db->attach_child_query( $users, <<SQL,
        SELECT
            auth_users_id,
            role
        FROM auth_users_roles_map AS aurm
            INNER JOIN auth_roles AS ar USING (auth_roles_id)
SQL
        'roles', 'auth_users_id'
    );

    $users = $db->attach_child_query( $users, <<SQL,
        SELECT
            au.auth_users_id,
            c.day,
            c.requests_count
        FROM auth_user_request_daily_counts AS c
            INNER JOIN auth_users AS au USING (email)
        ORDER BY
            day
SQL
        'requests', 'auth_users_id'
    );

    return $users;
}

sub list : Local : ActionClass('MC_REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    my $users = _get_users_list( $db, $c->req->params );

    my $entity = { users => $users };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'users' );

    $self->status_ok( $c, entity => $entity );
}

sub single : Local : ActionClass('MC_REST')
{
}

sub single_GET
{
    my ( $self, $c, $users_id ) = @_;

    my $users = _get_users_list( $c->dbis, { auth_users_id => $users_id } );

    $self->status_ok( $c, entity => { users => $users } );
}

sub list_roles : Local : ActionClass('MC_REST')
{

}

sub list_roles_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $roles = $db->query( "SELECT auth_roles_id, role, description FROM auth_roles" )->hashes();

    my $entity = { roles => $roles };

    $self->status_ok( $c, entity => $entity );
}

sub delete : Local : ActionClass('MC_REST')
{
}

sub delete_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/auth_users_id/ ] );

    my $user = $c->dbis->require_by_id( 'auth_users', $data->{ auth_users_id } );

    $c->dbis->query( "DELETE FROM auth_users WHERE auth_users_id = ?", $user->{ auth_users_id } );

    return $self->status_ok( $c, entity => { success => 1 } );
}

1;
