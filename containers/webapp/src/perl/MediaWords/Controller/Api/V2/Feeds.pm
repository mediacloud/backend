package MediaWords::Controller::Api::V2::Feeds;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use MediaWords::Controller::Api::V2::MC_REST_SimpleObject;
use MediaWords::JobManager::StatefulJob;

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
Readonly my $JOB_STATE_FIELD_LIST => "job_states_id, ( args->>'media_id' )::int media_id, state, message, last_updated";

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

    my $job_state = $db->query( <<SQL, $data->{ media_id }, $job_class )->hash;
select $JOB_STATE_FIELD_LIST
    from pending_job_states
    where
        ( args->>'media_id' )::int = \$1 and
        class = \$2
    order by job_states_id desc
    limit 1
SQL

    if ( !$job_state )
    {
        $db->begin;
        MediaWords::JobManager::StatefulJob::add_to_queue( $job_class, { media_id => $data->{ media_id } }, undef, $db );
        $job_state = $db->query( "select $JOB_STATE_FIELD_LIST from job_states order by job_states_id desc limit 1" )->hash;
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
        $job_states = $db->query( <<SQL, $media_id, $job_class )->hashes;
select $JOB_STATE_FIELD_LIST
    from job_states
    where
        class = \$2 and
        ( args->>'media_id' )::int = \$1
    order by last_updated desc
SQL
    }
    else
    {
        $job_states = $db->query( <<SQL, $job_class )->hashes;
select $JOB_STATE_FIELD_LIST
    from job_states
    where
        class = \$1
    order by last_updated desc
    limit 100
SQL
    }

    $self->status_ok( $c, entity => { job_states => $job_states } );
}

1;
