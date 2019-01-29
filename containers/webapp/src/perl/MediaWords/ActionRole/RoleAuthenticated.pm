package MediaWords::ActionRole::RoleAuthenticated;

#
# Authenticate by requiring that the user have one of the auth_roles returned by _get_auth_roles
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

    eval { $self->_require_role( $c, $self->_get_auth_roles ); };
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
