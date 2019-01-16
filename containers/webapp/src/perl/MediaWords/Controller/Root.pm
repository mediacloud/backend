package MediaWords::Controller::Root;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use base 'Catalyst::Controller';

use HTTP::Status qw(:constants);

# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
__PACKAGE__->config->{ namespace } = '';

sub default : Private
{
    my ( $self, $c ) = @_;

    $c->response->status( HTTP_NOT_FOUND );
    die "API endpoint was not found";
}

1;
