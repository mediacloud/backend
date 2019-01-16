package MediaWords::Controller::Status;

#
# Static page used by monitoring to test whether Apache + Catalyst works
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    $c->response->content_type( 'text/plain; charset=UTF-8' );
    return $c->res->body( 'Wo' . 'rks!' );
}

__PACKAGE__->meta->make_immutable;

1;
