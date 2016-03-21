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
        single_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        list_GET   => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        update_PUT => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub get_table_name
{
    return "tag_sets";
}

sub update : Local : ActionClass('REST')
{
}

sub update_PUT : Local
{
    my ( $self, $c, $id ) = @_;

    my $name        = $c->req->params->{ 'name' };
    my $label       = $c->req->params->{ 'label' };
    my $description = $c->req->params->{ 'description' };

    my $tag_set = $c->dbis->find_by_id( 'tag_sets', $id );

    die 'tag set not found ' unless defined( $tag_set );

    $self->die_unless_user_can_edit_tag_set_descriptors( $c, $tag_set );

    if ( defined( $name ) )
    {
        say STDERR "updating name to '$name'";
        $c->dbis->query( "UPDATE tag_sets set name = ? where tag_sets_id = ? ", $name, $id );
    }

    if ( defined( $label ) )
    {
        say STDERR "updating label to '$label'";
        $c->dbis->query( "UPDATE tag_sets set label = ? where tag_sets_id = ? ", $label, $id );
    }

    if ( defined( $description ) )
    {
        say STDERR "updating description to '$description'";
        $c->dbis->query( "UPDATE tag_sets set description = ? where tag_sets_id = ? ", $description, $id );
    }

    die unless defined( $name ) || defined( $label ) || defined( $description );

    $tag_set = $c->dbis->find_by_id( 'tag_sets', $id );

    $self->status_ok( $c, entity => $tag_set );

    return;
}

1;
