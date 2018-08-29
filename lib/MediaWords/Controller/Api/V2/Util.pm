package MediaWords::Controller::Api::V2::Util;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;

use MediaWords::Controller::Api::V2::MC_Controller_REST;
use MediaWords::DBI::Stories::AP;

use Moose;
use namespace::autoclean;

use Readonly;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    action => { is_syndicated_ap => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub is_syndicated_ap : Local : ActionClass('MC_REST')
{
}

# detect whether a given block of content is ap syndicated content
sub is_syndicated_ap_PUT
{
    my ( $self, $c ) = @_;

    my $content = $c->req->data->{ content };

    if ( !defined( $content ) )
    {
        die( "json input must include content field" );
    }

    my $is_syndicated = MediaWords::DBI::Stories::AP::is_syndicated( $c->dbis, { content => $content } );

    $self->status_ok( $c, entity => { is_syndicated => $is_syndicated ? 1 : 0 } );
}

1;
