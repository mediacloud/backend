package MediaWords::ActionRole::ApiKeyAuthenticated;

#
# Action role that requires its actions to authenticate via API key
#

use strict;
use warnings;

use Moose::Role;
use namespace::autoclean;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::DBI::Auth;

sub _api_key_is_invalid($$$)
{
    my ( $self, $c, $api_auth ) = @_;

    # user_for_api_token_catalyst() did the check already
    if (    defined( $api_auth )
        and ref( $api_auth ) eq ref( {} )
        and defined( $api_auth->{ email } )
        and length( $api_auth->{ email } ) > 0 )
    {
        return 0;
    }
    else
    {
        return 1;
    }
}

before execute => sub {
    my ( $self, $controller, $c ) = @_;

    # Check API key
    my $allow_unauth = MediaWords::Util::Config::get_config->{ mediawords }->{ allow_unauthenticated_api_requests } || 'no';
    if ( $allow_unauth ne 'yes' )
    {
        my $api_auth = MediaWords::DBI::Auth::user_for_api_token_catalyst( $c );

        if ( $self->_api_key_is_invalid( $c, $api_auth ) )
        {

            $controller->status_forbidden( $c, message => 'Invalid API key. Access denied.' );
            $c->detach();

            return 0;
        }

        $c->stash->{ auth_user } = $api_auth;
    }
};

1;
