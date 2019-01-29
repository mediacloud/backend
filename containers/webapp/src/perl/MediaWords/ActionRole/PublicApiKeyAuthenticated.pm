package MediaWords::ActionRole::PublicApiKeyAuthenticated;

#
# Action role that requires its actions to authenticate via API key
#

use strict;
use warnings;

use Moose::Role;
with 'MediaWords::ActionRole::AbstractAuthenticatedActionRole';
use namespace::autoclean;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use HTTP::Status qw(:constants);

around execute => sub {

    my $orig = shift;
    my $self = shift;
    my ( $controller, $c ) = @_;

    eval {
        my ( $user_email, $user_roles ) = $self->_user_email_and_roles( $c );
        unless ( $user_email and $user_roles )
        {
            $c->response->status( HTTP_FORBIDDEN );
            die 'Invalid API key or authentication cookie. Access denied.';
        }
    };
    if ( $@ )
    {
        my $message = $@;

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

    return $self->$orig( @_ );
};

1;
