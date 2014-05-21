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
use MediaWords::DBI::Auth;

before execute => sub {
    my ( $self, $controller, $c ) = @_;

    say STDERR "NonPublicApiKeyAuthenticated";

    # Check API key
    my $allow_unauth = MediaWords::Util::Config::get_config->{ mediawords }->{ allow_unauthenticated_api_requests } || 'no';
    if ( $allow_unauth ne 'yes' )
    {
        my ( $user_email, $user_roles ) = $self->_user_email_and_roles( $c );

        #say STDERR Dumper( $user_roles );

        unless ( $user_email and $user_roles )
        {
            $controller->status_forbidden( $c, message => 'Invalid API key. Access denied.' );
            $c->detach();
            return;
        }

        my $user_info = MediaWords::DBI::Auth::user_info( $c->dbis, $user_email );

        #say STDERR Dumper( $user_info );

        if ( !$user_info->{ non_public_api } )
        {
            #say STDERR "non public api access denied";
            $controller->status_forbidden( $c, message => 'Your API key does not allow access to this URL. Access denied.' );
            $c->detach();
            return;
        }
    }
};

1;
