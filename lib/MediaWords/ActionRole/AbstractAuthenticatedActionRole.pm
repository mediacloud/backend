package MediaWords::ActionRole::AbstractAuthenticatedActionRole;

#
# Action role that logs requests
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose::Role;
use namespace::autoclean;

use Data::Dumper;
use HTTP::Status qw(:constants);

use MediaWords::DBI::Auth;

sub _test_for_topic_permission
{
    my ( $self, $c, $permission_type ) = @_;

    my $path = $c->req->path;

    die( "unable to parse request path '$path' for topics_id" ) if ( $path !~ m~/topics/(\d+)/~ );

    my $topics_id = $1;

    my ( $user_email, $user_roles ) = $self->_user_email_and_roles( $c );
    unless ( $user_email and $user_roles )
    {
        $c->response->status( HTTP_FORBIDDEN );
        die 'Invalid API key or authentication cookie. Access denied.';
    }

    # admin users can read or write everything; admin-readonly users can read everything
    return if ( grep { $_ eq $MediaWords::DBI::Auth::Roles::ADMIN } @{ $user_roles } );
    return
      if ( ( $permission_type eq 'read' ) && grep { $_ eq $MediaWords::DBI::Auth::Roles::ADMIN_READONLY } @{ $user_roles } );

    my $permission_clauses = {
        read  => 'and ( ( tp.permission is not null ) or t.is_public )',
        write => "and tp.permission in ( 'write', 'admin' )",
        admin => "and tp.permission in ( 'admin' )"
    };
    my $permission_clause = $permission_clauses->{ $permission_type }
      || die( "Unknown permission type '$permission_type'" );

    my $permission = $c->dbis->query( <<SQL, $user_email, $topics_id )->hash;
select 1
    from auth_users u
        join topics t on ( t.topics_id = \$2 )
        left join topic_permissions tp on ( u.auth_users_id = tp.auth_users_id and tp.topics_id = t.topics_id )
    where
        u.email = \$1
        $permission_clause
SQL

    die( "User lacks $permission_type permission for the requested topic" ) unless ( $permission );
}

sub _authenticate_topic
{
    my ( $self, $c, $permission_type ) = @_;

    eval { $self->_test_for_topic_permission( $c, $permission_type ) };
    if ( $@ )
    {
        my $message = $@;

        $c->response->status( HTTP_FORBIDDEN );
        push( @{ $c->stash->{ auth_errors } }, $message );
        $c->detach();
        return undef;
    }
    elsif ( $c->req->params->{ quit_after_auth } )
    {
        $c->stash->{ quit_after_auth } = 1;
        $c->detach();
        return undef;
    }

}

# Return an array with user email and roles (authenticated either via API key or normal means)
sub _user_email_and_roles($$)
{
    my ( $self, $c ) = @_;

    my $user_email = undef;
    my @user_roles;

    # 1. If the request has the "key" parameter, force authenticating via API
    #    key (even if the user is logged in)
    if ( $c->request->param( 'key' ) )
    {

        my $api_auth = undef;
        if ( $c->stash->{ api_auth } )
        {
            $api_auth = $c->stash->{ api_auth };
        }
        else
        {
            $api_auth = MediaWords::DBI::Auth::user_for_api_token_catalyst( $c );
        }

        if ( $api_auth )
        {
            $user_email = $api_auth->{ email };
            @user_roles = @{ $api_auth->{ roles } };

            $c->stash->{ api_auth } = $api_auth;
        }

    }

    # 2. If the request doesn't have the "key" parameter, but the user is
    #    logged in, let it go through anyway
    elsif ( $c->user )
    {

        $user_email = $c->user->username;
        @user_roles = $c->user->roles;

    }
    else
    {
        TRACE( "user not logged in and key paramater not provided" );
    }

    return ( $user_email, \@user_roles );
}

1;
