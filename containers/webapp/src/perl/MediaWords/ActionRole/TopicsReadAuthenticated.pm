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

use HTTP::Status qw(:constants);

around execute => sub {

    my $orig = shift;
    my $self = shift;
    my ( $controller, $c ) = @_;

    $self->_authenticate_topic( $c, 'read' );

    return $self->$orig( @_ );
};

1;
