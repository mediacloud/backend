package MediaWords::Controller::Api::V2::Stats;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub list : Local : ActionClass('MC_REST')
{
}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $stats = $c->dbis->query( "select * from mediacloud_stats" )->hash;

    # refresh_mediacloud_stats needs to be run via cron daily
    die( "stats have not been generated" ) unless ( $stats );

    $self->status_ok( $c, entity => $stats );
}

1;
