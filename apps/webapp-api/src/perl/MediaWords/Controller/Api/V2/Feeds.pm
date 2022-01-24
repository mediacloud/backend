package MediaWords::Controller::Api::V2::Feeds;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;

use MediaWords::Controller::Api::V2::MC_REST_SimpleObject;
use MediaWords::Job::StatefulBroker;

use Moose;
use namespace::autoclean;

use Readonly;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

__PACKAGE__->config(
    action => {
        create        => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
        update        => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
        scrape        => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
        scrape_status => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
    }
);

# sql clause for fields to query from job_states for api publication
Readonly my $JOB_STATE_FIELD_LIST => "job_states_id, ( args->>'media_id' )::bigint media_id, state, message, last_updated";

sub default_output_fields
{
    return [
        qw ( name url media_id feeds_id type active last_new_story_time
          last_attempted_download_time last_successful_download_time )
    ];
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
    return [ qw/name url type active/ ];
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

sub scrape_GET
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/media_id/ ] );

    my $db = $c->dbis;

    my $job_class = 'MediaWords::Job::RescrapeMedia';

    my $job_state = $db->query( <<SQL,
        SELECT $JOB_STATE_FIELD_LIST
        FROM pending_job_states
        WHERE
            (args->>'media_id')::BIGINT = \$1 AND
            class = \$2
        ORDER BY job_states_id DESC
        LIMIT 1
SQL
        $data->{ media_id }, $job_class
    )->hash;

    if ( !$job_state )
    {
        $db->begin;
        MediaWords::Job::StatefulBroker->new( $job_class )->add_to_queue( { media_id => $data->{ media_id } } );
        $job_state = $db->query( <<SQL
            SELECT $JOB_STATE_FIELD_LIST
            FROM job_states
            ORDER BY job_states_id DESC
            LIMIT 1
SQL
        )->hash;
        $db->commit;

        die( "Unable to find job state from queued job" ) unless ( $job_state );
    }

    return $self->status_ok( $c, entity => { job_state => $job_state } );
}

sub scrape_status : Local : ActionClass( 'MC_REST' )
{
}

sub scrape_status_GET
{
    my ( $self, $c ) = @_;

    my $media_id = int( $c->req->params->{ media_id } // 0 );

    my $job_class = 'MediaWords::Job::RescrapeMedia';

    my $db = $c->dbis;

    my $job_states;

    if ( $media_id )
    {
        $job_states = $db->query( <<SQL,
            SELECT $JOB_STATE_FIELD_LIST
            FROM job_states
            WHERE
                class = \$2 AND
                ( args->>'media_id' )::BIGINT = \$1
            ORDER BY last_updated DESC
SQL
            $media_id, $job_class
        )->hashes;
    }
    else
    {
        $job_states = $db->query( <<SQL,
            SELECT $JOB_STATE_FIELD_LIST
            FROM job_states
            WHERE class = \$1
            ORDER BY last_updated DESC
            LIMIT 100
SQL
            $job_class
        )->hashes;
    }

    $self->status_ok( $c, entity => { job_states => $job_states } );
}

1;
