package MediaWords::Controller::Api::V2::Topics::Snapshots;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Moose;
use namespace::autoclean;

use MediaWords::DBI::Snapshots;
use MediaWords::Job::StatefulBroker;
use MediaWords::KeyValueStore::PostgreSQL;
use MediaWords::Util::Compress;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    action => {
        create          => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
        list            => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        generate        => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
        generate_status => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        word2vec_model  => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
    }
);

Readonly my $JOB_STATE_FIELD_LIST =>
"job_states_id, ( args->>'topics_id' )::bigint topics_id, ( args->>'snapshots_id' )::bigint snapshots_id, state, message, last_updated";

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;
    $c->stash->{ topics_id } = int( $topics_id );
}

sub snapshots : Chained('apibase') : PathPart('snapshots') : CaptureArgs(1)
{
    my ( $self, $c, $snapshots_id ) = @_;
    $c->stash->{ snapshots_id } = int( $snapshots_id );
}

sub list : Chained('apibase') : PathPart( 'snapshots/list' ) : Args(0) : ActionClass('MC_REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id = $c->stash->{ topics_id };

    my $snapshots = $db->query(
        <<SQL,
        SELECT
            snapshots_id,
            snapshot_date,
            note,
            state,
            searchable,
            message,
            seed_queries
        FROM snapshots
        WHERE topics_id = \$1
        ORDER BY snapshots_id DESC
SQL
        $topics_id
    )->hashes;

    $snapshots = $db->attach_child_query(
        $snapshots, <<SQL,
        SELECT
            snap_word2vec_models_id AS models_id,

            -- FIXME snapshots_id gets into resulting hashes, not sure how to
            -- get rid of it with attach_child_query()
            snapshots_id,

            creation_date
        FROM snap.word2vec_models
SQL
        'word2vec_models', 'snapshots_id'
    );

    $self->status_ok( $c, entity => { snapshots => $snapshots } );
}

sub create : Chained('apibase') : PathPart( 'snapshots/create' ) : Args(0) : ActionClass('MC_REST')
{
}

sub create_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id = $c->stash->{ topics_id };
    my $topic = $db->require_by_id( 'topics', $topics_id );

    my $data = $c->req->data;

    my $note = $data->{ note } || '';

    my $snapshot = MediaWords::DBI::Snapshots::create_snapshot_row( $db, $topic );

    $self->status_ok( $c, entity => { snapshot => $snapshot } );
}

sub generate : Chained('apibase') : PathPart( 'snapshots/generate' ) : Args(0) : ActionClass('MC_REST')
{
}

sub generate_GET
{
    my ( $self, $c ) = @_;

    my $topics_id = $c->stash->{ topics_id };

    my $note = $c->req->data->{ post } || '' if ( $c->req->data );
    my $snapshots_id = $c->req->data->{ snapshots_id } if ( $c->req->data );

    my $job_class = 'MediaWords::Job::TM::SnapshotTopic';

    my $db = $c->dbis;

    $db->begin;

    MediaWords::Job::StatefulBroker->new( 'MediaWords::Job::TM::SnapshotTopic' )->add_to_queue( {
        snapshots_id => $snapshots_id,
        topics_id => $topics_id,
        note => $note,
    } );
    my $job_state = $db->query( <<SQL
        SELECT $JOB_STATE_FIELD_LIST
        FROM job_states
        ORDER BY job_states_id DESC
        LIMIT 1
SQL
    )->hash;
    $db->commit;

    die( "Unable to find job state from queued job" ) unless ( $job_state );

    return $self->status_ok( $c, entity => { job_state => $job_state } );
}

sub generate_status : Chained('apibase') : PathPart( 'snapshots/generate_status' ) : Args(0) : ActionClass('MC_REST')
{
}

sub generate_status_GET
{
    my ( $self, $c ) = @_;

    my $topics_id = $c->stash->{ topics_id };

    my $job_class = 'MediaWords::Job::TM::SnapshotTopic';

    my $db = $c->dbis;

    my $job_states;

    $job_states = $db->query( <<SQL,
        SELECT $JOB_STATE_FIELD_LIST
        FROM job_states
        WHERE
            class = ? AND
            ( args->>'topics_id' )::BIGINT = ?
        ORDER BY last_updated DESC
SQL
        $job_class, $topics_id
    )->hashes;

    $self->status_ok( $c, entity => { job_states => $job_states } );
}

sub word2vec_model : Chained('snapshots') : Args(1) : ActionClass('MC_REST')
{
}

sub word2vec_model_GET
{
    my ( $self, $c, $models_id ) = @_;

    my $db = $c->dbis;

    my $topics_id = int( $c->stash->{ topics_id } );
    unless ( $topics_id )
    {
        die "topics_id is not set.";
    }

    my $snapshots_id = int( $c->stash->{ snapshots_id } );
    unless ( $snapshots_id )
    {
        die "snapshots_id is not set.";
    }

    unless ( $models_id )
    {
        die "models_id is not set.";
    }

    my $model = $db->select(
        'snap.word2vec_models',
        'raw_data',
        {
            'topics_id' => $topics_id,
            'snapshots_id' => $snapshots_id,
            'snap_word2vec_models_id' => $models_id,
        },
    )->hash();
    unless ( $model ) {
        die "Model $models_id for topic $topics_id, snapshot $snapshots_id was not found";
    }

    my $compressed_model_data = $model->{'raw_data'};

    my $model_data = MediaWords::Util::Compress::gunzip( $compressed_model_data );

    my $filename = "word2vec-topic_$topics_id-snapshot_$snapshots_id-model_$models_id.bin";

    $c->response->content_type( 'application/octet-stream' );
    $c->response->header( 'Content-Disposition' => "attachment; filename=$filename" );
    $c->response->content_length( bytes::length( $model_data ) );
    return $c->res->body( $model_data );
}

1;
