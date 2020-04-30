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
use Readonly;

use Catalyst::Authentication::Credential::MediaWords::APIKey;
use MediaWords::DBI::Auth;

Readonly our $INVALID_API_KEY_MESSAGE => <<EOF;
Invalid API key. All API keys were reset on April 30, 2020, so make sure you are using a new one.'
EOF


# test whether the authenticated user has $permission_type access to the topic in the path of the currently requested
# url.   Queries the topics_with_user_permission view to determine the permissions for the current user.
sub _test_for_topic_permission
{
    my ( $self, $c, $permission_type ) = @_;

    my $path = $c->req->path;

    my $topics_id;

    $topics_id = $1 if ( $path =~ m~/topics/(\d+)/~ );

    die( "unable to determine topics_id for request" ) unless ( $topics_id );

    my ( $user_email, $user_roles ) = $self->_user_email_and_roles( $c );
    unless ( $user_email and $user_roles )
    {
        $c->response->status( HTTP_FORBIDDEN );
        die $INVALID_API_KEY_MESSAGE;
    }

    my $topic = $c->dbis->query( <<SQL, $topics_id, $user_email )->hash;
select t.*
    from topics_with_user_permission t
        join auth_users u using ( auth_users_id )
    where
        t.topics_id = \$1 and
        u.email = \$2
SQL

    my $user_permission = $topic->{ user_permission };

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

    my $db = $c->dbis;

    my $user_email = undef;
    my $user_roles;

    my $api_key_param = $Catalyst::Authentication::Credential::MediaWords::APIKey::API_KEY_FIELD;

    # 1. If the request has the API key parameter, force authenticating via API
    #    key (even if the user is logged in)
    if ( $c->request->param( $api_key_param ) )
    {

        my $api_auth = undef;
        if ( $c->stash->{ api_auth } )
        {
            $api_auth = $c->stash->{ api_auth };
        }
        else
        {
            if ( $c->authenticate( { key => $c->request->param( $api_key_param ) }, $MediaWords::AUTH_REALM_API_KEY ) )
            {
                $api_auth = MediaWords::DBI::Auth::Info::user_info( $db, $c->user->username );
            }
        }

        if ( $api_auth )
        {
            $user_email = $api_auth->email();
            $user_roles = $api_auth->role_names();

            $c->stash->{ api_auth } = $api_auth;
        }

    }

    # 2. If the request doesn't have the "key" parameter, but the user is
    #    logged in, let it go through anyway
    elsif ( $c->user )
    {

        $user_email = $c->user->username;
        $user_roles = \@{ $c->user->roles };

    }
    else
    {
        TRACE( "user not logged in and key paramater not provided" );
    }

    return ( $user_email, $user_roles );
}

# require one of the given roles for authentication.  return anything if one of the given roles is found. die if not.
sub _require_role($$$)
{
    my ( $self, $c, $roles ) = @_;

    my ( $user_email, $user_roles ) = $self->_user_email_and_roles( $c );
    unless ( $user_email and $user_roles )
    {
        $c->response->status( HTTP_FORBIDDEN );
        die $INVALID_API_KEY_MESSAGE;
    }

    for my $role ( @{ $roles } )
    {
        return 1 if ( grep { $_ eq $role } @{ $user_roles } );
    }

    $c->response->status( HTTP_FORBIDDEN );
    die( "User lacks one of these required permissions for the requested page: " . join( ', ', @{ $roles } ) );
}

1;
