package MediaWords::ActionRole::ApiKeyAuthenticated;

#
# Action role that requires its actions to authenticate via API key
#

use strict;
use warnings;

use Moose::Role;
with 'MediaWords::ActionRole::AbstractAuthenticatedActionRole';
use namespace::autoclean;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use HTTP::Status qw(:constants);

before execute => sub {
    my ( $self, $controller, $c ) = @_;

    # Check API key
    my $allow_unauth = MediaWords::Util::Config::get_config->{ mediawords }->{ allow_unauthenticated_api_requests } || 'no';
    if ( $allow_unauth ne 'yes' )
    {
        my ( $user_email, $user_roles ) = $self->_user_email_and_roles( $c );
        unless ( $user_email and $user_roles )
        {
            $c->response->status( HTTP_FORBIDDEN );
            $c->error( 'Invalid API key or authentication cookie. Access denied.' );
            $c->detach();
            return;
        }
    }
};

1;
