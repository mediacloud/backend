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

sub _authenticate_topic
{
    my ( $self, $c, $permission_type ) = @_;

    my $path = $c->req->path;
    if ( $path !~ m~/topics/(\d+)/~ )
    {
        die( "unable to parse request path '$path' for topics_id" );
    }

    my $topics_id = $1;

    my ( $user_email, $user_roles ) = $self->_user_email_and_roles( $c );
    unless ( $user_email and $user_roles )
    {
        $c->response->status( HTTP_FORBIDDEN );
        die 'Invalid API key or authentication cookie. Access denied.';
    }

    die( Dumper( $user_roles ) );

    my $permission_clause;
    if ( $permission_type eq 'read' )
    {
        $permission_clause = '';
    }
    elsif ( $permission_type eq 'write' )
    {
        $permission_clause = "and tp.permission in ( 'write', 'admin' ) )";
    }
    elsif ( $permission_type eq 'admin' )
    {
        $permission_clause = "and tp.permission in ( 'admin' )";
    }
    else
    {
        die( "Unknown permission type '$permission_type'" );
    }

    my $permission = $c->dbis->query( <<SQL, $user_email, $topics_id )->hash;
select 1
from auth_users u
    left join topic_permissions tp using ( auth_users_id )
    left join auth_user_roles r
where
    u.email = \$1 and
    topics_id = \$2
    $permission_clause
union

SQL

    die( 'User lacks read permission for the requested topic' ) unless ( $permission );
}

# Return an array with user email and roles (authenticated either via API key
# or normal means)
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
        ERROR "user not logged in and key paramater not provided";
    }

    return ( $user_email, \@user_roles );
}

1;
