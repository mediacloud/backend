package MediaWords::ActionRole::AbstractAuthenticatedActionRole;

#
# Action role that logs requests
#

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Moose::Role;
use namespace::autoclean;

use Data::Dumper;
use MediaWords::DBI::Auth;

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
        say STDERR "user not logged in and key paramater not provided";
    }

    return ( $user_email, \@user_roles );
}

1;
