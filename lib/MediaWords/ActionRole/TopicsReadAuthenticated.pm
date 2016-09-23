package MediaWords::ActionRole::TopicsReadAuthenticated;

#
# Action role that requires read permission for the given topic
#

use strict;
use warnings;

use Moose::Role;
with 'MediaWords::ActionRole::AbstractAuthenticatedActionRole';
use namespace::autoclean;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use HTTP::Status qw(:constants);

around execute => sub {

    my ( $orig, $self, $controller, $c ) = @_;

    eval { $self->_authenticate_topic( $c, 'read' ); };
    if ( $@ )
    {
        my $message = $@;

        $c->error( 'Authentication error: ' . $@ );
        $c->detach();
        return undef;
    }

    return $self->$orig( @_ );
};

1;
