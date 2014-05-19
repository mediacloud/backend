package MediaWords::ActionRole::NonPublicApiKeyAuthenticated;

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

before execute => sub {
    my ( $self, $controller, $c ) = @_;

    # Check API key
    my $allow_unauth = MediaWords::Util::Config::get_config->{ mediawords }->{ allow_unauthenticated_api_requests } || 'no';
    if ( $allow_unauth ne 'yes' )
    {
        my ( $user_email, $user_roles ) = $self->_user_email_and_roles( $c );
        unless ( $user_email and $user_roles )
        {
            $controller->status_forbidden( $c, message => 'Invalid API key. Access denied.' );
            $c->detach();
            return;
        }
    }
};

1;
