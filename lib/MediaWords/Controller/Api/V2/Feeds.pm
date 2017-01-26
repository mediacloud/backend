package MediaWords::Controller::Api::V2::Feeds;
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
        create => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
        update => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub default_output_fields
{
    return [ qw ( name url media_id feeds_id feed_type ) ];
}

sub get_table_name
{
    return "feeds";
}

sub list_query_filter_field
{
    return 'media_id';
}

sub get_update_fields($)
{
    return [ qw/name url feed_type feed_status/ ];
}

sub update : Local : ActionClass('MC_REST')
{
}

sub update_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/feeds_id/ ] );

    my $feed = $c->dbis->require_by_id( 'feeds', $data->{ feeds_id } );

    my $input = { map { $_ => $data->{ $_ } } grep { exists( $data->{ $_ } ) } @{ $self->get_update_fields } };

    my $row = $c->dbis->update_by_id( 'feeds', $data->{ feeds_id }, $input );

    return $self->status_ok( $c, entity => { feed => $row } );
}

sub create : Local : ActionClass( 'MC_REST' )
{
}

sub create_GET
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/media_id name url/ ] );

    my $fields = [ 'media_id', @{ $self->get_update_fields } ];
    my $input = { map { $_ => $data->{ $_ } } grep { exists( $data->{ $_ } ) } @{ $fields } };
    my $row = $c->dbis->create( 'feeds', $input );

    return $self->status_ok( $c, entity => { feed => $row } );
}

sub scrape : Local : ActionClass( 'MC_REST' )
{
}

sub scrape_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/media_id/ ] );

    my $db = $c->dbi8;

    my $job_state = $db->query( <<SQL, $data->{ media_id } )->hash;
select *
    from job_states
    where
        ( args->'media_id' )::int = ? and
        class = 'MediaWords::Job::TM::RescrapeMedia' and
        state not in ( 'completed successfully', 'error' )
SQL

    if ( !$job_state )
    {
        $db->begin;
        MediaWords::Job::RescapeMedia->add_to_queue( { media_id => $data->{ media_id } } );
        $job_state = $db->require_by_id( 'job_states', $job_state->{ job_states_id } );
    }

    $job_state->{ args } = MediaWords::Util::JSON::decode_json( $job_state->{ args } );

    return $self->status_ok( $c, entity => { job_state => $job_state } );
}

1;
