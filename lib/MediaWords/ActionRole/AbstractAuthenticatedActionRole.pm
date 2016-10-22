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

# test whether the authenticated user has $permission_type access to the topic in the path of the currently requested
# url.   Queries the topics_with_user_permission view to determine the permissions for the current user.
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

    return if ( grep { $_ eq $MediaWords::DBI::Auth::Roles::ADMIN } @{ $user_roles } );
    return
      if ( ( $permission_type eq 'read' ) && grep { $_ eq $MediaWords::DBI::Auth::Roles::ADMIN_READONLY } @{ $user_roles } );

    my $topic = $c->dbis->query( <<SQL, $topics_id, $user_email )->hash;
select t.*
    from topics_with_user_permission t
        join auth_users u using ( auth_users_id )
    where
        t.topics_id = \$1 and
        u.email = \$2
SQL

    my $user_permission = $topic->{ user_permission };

    return if ( $topic->{ is_public } && ( $topic->{ user_permission } eq 'read' ) );

    my $allowed_permissions_lookup = {
        read  => [ qw/read write admin/ ],
        write => [ qw/write admin/ ],
        admin => [ qw/admin/ ]
    };

    my $allowed_permissions = $allowed_permissions_lookup->{ $permission_type };
    die( "Unknown permission type '$permission_type'" ) unless ( $allowed_permissions );

    if ( !( grep { $_ eq $user_permission } @{ $allowed_permissions } ) )
    {
        $c->response->status( HTTP_FORBIDDEN );
        die( "User lacks $permission_type permission for the requested topic" );
    }
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
