package MediaWords::Controller::Api::V2::Topics::Snapshots;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Moose;
use namespace::autoclean;

use MediaWords::KeyValueStore::PostgreSQL;

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
"job_states_id, ( args->>'topics_id' )::int topics_id, ( args->>'snapshots_id' )::int snapshots_id, state, message, last_updated";

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
            message
        FROM snapshots
        WHERE topics_id = \$1
        ORDER BY snapshots_id DESC
SQL
        $topics_id
    )->hashes;

    $snapshots = $db->attach_child_query(
        $snapshots, <<SQL,
        SELECT
            word2vec_models_id AS models_id,

            -- FIXME snapshots_id gets into resulting hashes, not sure how to
            -- get rid of it with attach_child_query()
            object_id AS snapshots_id,

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

    my $snapshot = $db->query( <<SQL, $note, 'created but not queued', $topics_id )->hash();
insert into snapshots ( topics_id, snapshot_date, start_date, end_date, note, state )
    select topics_id, now(), start_date, end_date, ?, ? from topics where topics_id = ?
    returning *
SQL

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

    my $job_class = 'MediaWords::Job::TM::SnapshotTopic';

    my $db = $c->dbis;

    my $job_state = $db->query( <<SQL, $topics_id, $job_class )->hash;
select $JOB_STATE_FIELD_LIST
    from pending_job_states
    where
        ( args->>'topics_id' )::int = \$1 and
        class = \$2
    order by job_states_id desc
SQL

    if ( !$job_state )
    {
        $db->begin;
        MediaWords::JobManager::Job::add_to_queue( 'MediaWords::Job::TM::SnapshotTopic', { topics_id => $topics_id, note => $note }, undef, $db );
        $job_state = $db->query( "select $JOB_STATE_FIELD_LIST from job_states order by job_states_id desc limit 1" )->hash;
        $db->commit;

        die( "Unable to find job state from queued job" ) unless ( $job_state );
    }

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

    $job_states = $db->query( <<SQL, $topics_id, $job_class )->hashes;
select $JOB_STATE_FIELD_LIST
    from job_states
    where
        class = \$2 and
        ( args->>'topics_id' )::int = \$1
    order by last_updated desc
SQL

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

    my $model_store = MediaWords::KeyValueStore::PostgreSQL->new( { table => 'snap.word2vec_models_data' } );
    my $model_data = $model_store->fetch_content( $db, $models_id );
    unless ( defined $model_data )
    {
        die "Model data for topic $topics_id, snapshot $snapshots_id, model $models_id is undefined.";
    }

    my $filename = "word2vec-topic_$topics_id-snapshot_$snapshots_id-model_$models_id.bin";

    $c->response->content_type( 'application/octet-stream' );
    $c->response->header( 'Content-Disposition' => "attachment; filename=$filename" );
    $c->response->content_length( bytes::length( $model_data ) );
    return $c->res->body( $model_data );
}

1;
