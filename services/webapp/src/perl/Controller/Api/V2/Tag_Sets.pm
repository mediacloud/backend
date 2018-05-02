package MediaWords::Controller::Api::V2::Tag_Sets;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use MediaWords::Controller::Api::V2::MC_REST_SimpleObject;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

__PACKAGE__->config(
    action => {
        single => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        list   => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        create => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        update => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub get_table_name
{
    return "tag_sets";
}

sub get_update_fields($)
{
    return [ qw/name label description show_on_media show_on_stories/ ];
}

sub update : Local : ActionClass('MC_REST')
{
}

sub update_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/tag_sets_id/ ] );

    my $tag_set = $c->dbis->require_by_id( 'tag_sets', $data->{ tag_sets_id } );

    my $input = { map { $_ => $data->{ $_ } } grep { exists( $data->{ $_ } ) } @{ $self->get_update_fields } };

    $input->{ show_on_media }   = normalize_boolean_for_db( $input->{ show_on_media } );
    $input->{ show_on_stories } = normalize_boolean_for_db( $input->{ show_on_stories } );

    my $row = $c->dbis->update_by_id( 'tag_sets', $data->{ tag_sets_id }, $input );

    return $self->status_ok( $c, entity => { tag_set => $row } );
}

sub create : Local : ActionClass( 'MC_REST' )
{
}

sub create_GET
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/name label/ ] );

    my $input = { map { $_ => $data->{ $_ } } grep { exists( $data->{ $_ } ) } @{ $self->get_update_fields } };

    $input->{ show_on_media }   = normalize_boolean_for_db( $input->{ show_on_media } );
    $input->{ show_on_stories } = normalize_boolean_for_db( $input->{ show_on_stories } );

    my $row = $c->dbis->create( 'tag_sets', $input );

    return $self->status_ok( $c, entity => { tag_set => $row } );
}

1;
