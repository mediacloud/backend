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
        delete from auth_users_roles_map aurm
            using auth_roles ar
            where
                aurm.auth_roles_id = ar.auth_roles_id and
                aurm.auth_users_id = \$1 and
                not ( ar.role = any( \$2 ) )
SQL

    $db->query( <<SQL, $user->{ auth_users_id }, $roles );
        insert into auth_users_roles_map ( auth_users_id, auth_roles_id )
            select \$1, ar.auth_roles_id
                from auth_roles ar
                where ar.role = any( \$2 )
            on conflict do nothing
SQL

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

    my $update_fields = [ qw/email full_name notes active max_topic_stories/ ];

    my $input = { map { $_ => $data->{ $_ } } grep { exists( $data->{ $_ } ) } @{ $update_fields } };

    my $db = $c->dbis;

    $db->update_by_id( 'auth_users', $data->{ auth_users_id }, $input ) if ( scalar( keys( %{ $input } ) ) );

    if ( exists( $data->{ weekly_requests_limit } ) )
    {
        $db->query(
            "update auth_user_limits set weekly_requests_limit = ? where auth_users_id = ?",
            $data->{ weekly_requests_limit },
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
        $id_clause = "auth_users_id in ( $users_ids_list )";
    }

    my $search_clause = '1=1';
    if ( $search )
    {
        my $q_search = $db->quote( $search );
        $search_clause = "( full_name ilike '%'||$q_search||'%' or email ilike '%'||$q_search||'%' )";
    }

    my $users = $db->query( <<SQL, $limit, $offset )->hashes();
        select auth_users_id, email, full_name, notes, active, created_date, max_topic_stories, weekly_requests_limit
            from auth_users au
                join auth_user_limits aul using ( auth_users_id )
            where
                $id_clause and
                $search_clause
            limit \$1
            offset \$2
SQL

    $users = $db->attach_child_query( $users, <<SQL, 'roles', 'auth_users_id' );
        select auth_users_id, role
            from auth_users_roles_map aurm
                join auth_roles ar using ( auth_roles_id )  
SQL

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

    my $roles = $db->query( "select auth_roles_id, role, description from auth_roles" )->hashes();

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

    $c->dbis->query( "delete from auth_users where auth_users_id = ?", $user->{ auth_users_id } );

    return $self->status_ok( $c, entity => { success => 1 } );
}

1;
