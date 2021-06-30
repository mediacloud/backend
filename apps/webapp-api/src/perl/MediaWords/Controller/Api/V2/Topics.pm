package MediaWords::Controller::Api::V2::Topics;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use HTTP::Status qw(:constants);
use Readonly;

use Moose;
use namespace::autoclean;

use MediaWords::Solr;
use MediaWords::Solr::Query;
use MediaWords::Solr::Query::Parse;
use MediaWords::Job::StatefulBroker;

BEGIN
{
    extends 'MediaWords::Controller::Api::V2::MC_Controller_REST';
    use MediaWords::DBI::Auth::Roles;
}

__PACKAGE__->config(
    action => {
        info              => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        list              => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        list_timespan_files => { Does => [ qw(~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        list_snapshot_files => { Does => [ qw(~AdminAuthenticated ~Throttled ~Logged ) ] },
        single            => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        create            => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        update            => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
        spider            => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
        spider_status     => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        reset             => { Does => [ qw( ~TopicsAdminAuthenticated ~Throttled ~Logged ) ] },
        add_seed_query    => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
        remove_seed_query => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
    }
);

Readonly::Scalar my $TOPICS_EDIT_FIELDS => [
    qw/name solr_seed_query description max_iterations start_date end_date platform is_public max_stories is_logogram is_story_index_ready/
];

Readonly::Scalar my $JOB_STATE_FIELD_LIST =>
"job_states_id, ( args->>'topics_id' )::bigint topics_id, ( args->>'snapshots_id' )::int snapshots_id, state, message, last_updated";

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;

    $c->stash->{ topics_id } = $topics_id;
}

sub _get_topics_list($$$)    # sql clause for fields to query from job_states for api publication
{
    my ( $db, $params, $auth_users_id ) = @_;

    my $name      = $params->{ name } || '';
    my $topics_id = $params->{ topics_id };
    my $public    = $params->{ public };

    my $limit  = $params->{ limit };
    my $offset = $params->{ offset };

    my $id_clause = '';
    if ( $topics_id )
    {
        $id_clause = 't.topics_id = ' . int( $topics_id ) . ' and ';
    }

    my $public_clause = '';
    if ( defined( $public ) )
    {
        $public_clause = $public ? "t.is_public and" : "not t.is_public and";
    }

    my $topics = $db->query(
        <<SQL,
            SELECT
                t.topics_id,
                t.name,
                t.pattern,
                t.solr_seed_query,
                t.solr_seed_query_run,
                t.description,
                t.max_iterations,
                t.state,
                t.message,
                t.is_public,
                t.start_date,
                t.end_date,
                t.platform,
                t.mode,
                MIN(p.auth_users_id) AS auth_users_id,
                MIN(p.user_permission) AS user_permission,
                t.job_queue,
                t.max_stories,
                t.is_logogram,
                t.is_story_index_ready,
                0 ch_monitor_id
            FROM topics AS t
                JOIN topics_with_user_permission AS p USING (topics_id)
                LEFT JOIN snapshots AS snap ON t.topics_id = snap.topics_id
            WHERE
                $id_clause
                $public_clause
                p.auth_users_id= \$1 AND
                t.name ILIKE \$2 AND
                p.user_permission != 'none'
            GROUP BY t.topics_id
            ORDER BY
                t.state = 'completed',
                t.state,
                MAX(COALESCE(snap.snapshot_date, '2000-01-01'::date)) DESC
            LIMIT \$3
            OFFSET \$4
SQL
        $auth_users_id, '%' . $name . '%', $limit, $offset
    )->hashes;

    $topics = $db->attach_child_query(
        $topics, <<SQL,
        SELECT
            m.media_id,
            m.name,
            tmm.topics_id
        FROM media AS m
            JOIN topics_media_map AS tmm USING (media_id)
SQL
        'media', 'topics_id'
    );

    $topics = $db->attach_child_query(
        $topics, <<SQL,
        SELECT
            t.tags_id,
            t.tag,
            t.label,
            t.description,
            tmtm.topics_id
        FROM tags AS t
            JOIN topics_media_tags_map AS tmtm USING (tags_id)
SQL
        'media_tags', 'topics_id'
    );

    $topics = $db->attach_child_query(
        $topics, <<SQL,
        SELECT
            tp.topics_id,
            au.auth_users_id,
            au.email,
            au.full_name
        FROM topic_permissions AS tp
            JOIN auth_users AS au USING (auth_users_id)
    where
        tp.permission = 'admin'
SQL
        'owners', 'topics_id'
    );

    $topics = $db->attach_child_query(
        $topics, <<SQL,
        WITH js as (
            SELECT
                js.job_states_id,
                js.class,
                js.state,
                js.message,
                js.last_updated,
                ( js.args->>'topics_id' )::BIGINT topics_id,
                ( js.args->>'snapshots_id' )::BIGINT snapshots_id
            FROM job_states AS js
            ORDER BY job_states_id DESC
        )

        SELECT * FROM js
SQL
        'job_states', 'topics_id'
    );

    $topics = $db->attach_child_query( $topics, "select * from topic_seed_queries", 'topic_seed_queries', 'topics_id' );

    return $topics;
}

sub list : Local : ActionClass('MC_REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    my $auth_users_id = $c->stash->{ api_auth }->user_id();

    my $topics = _get_topics_list( $db, $c->req->params, $auth_users_id );

    my $entity = { topics => $topics };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'topics' );

    $self->status_ok( $c, entity => $entity );
}

sub single : Local : ActionClass('MC_REST')
{
}

sub single_GET
{
    my ( $self, $c, $topics_id ) = @_;

    my $auth_users_id = $c->stash->{ api_auth }->user_id();

    my $topics = _get_topics_list( $c->dbis, { topics_id => $topics_id }, $auth_users_id );

    $self->status_ok( $c, entity => { topics => $topics } );
}

# reset the data in the topics_media_map and topics_media_tags_map tables for the given topic
sub _set_topic_media($$$$)
{
    my ( $db, $topic, $media_ids, $media_tags_ids ) = @_;

    my $topics_id = $topic->{ topics_id };

    if ( $media_ids )
    {
        $db->query( "delete from topics_media_map where topics_id = ?", $topics_id );
        for my $media_id ( @{ $media_ids } )
        {
            $db->query( "insert into topics_media_map ( topics_id, media_id ) values ( ?, ? )", $topics_id, $media_id );
        }
    }

    if ( $media_tags_ids )
    {
        $db->query( "delete from topics_media_tags_map where topics_id = ?", $topics_id );
        for my $tags_id ( @{ $media_tags_ids } )
        {
            $db->query( "insert into topics_media_tags_map ( topics_id, tags_id ) values ( ?, ? )", $topics_id, $tags_id );
        }
    }
}

# die if the user is not an admin and the max_stories is great than the max_stories field in auth_users for the  user
sub _validate_max_stories($$$)
{
    my ( $db, $max_stories, $auth_users_id ) = @_;

    my $auth_user = $db->require_by_id( 'auth_users', $auth_users_id );
    my $auth_user_limits = $db->query(<<SQL,
        SELECT *
        FROM auth_user_limits
        WHERE auth_users_id = ?
SQL
        $auth_users_id
    )->hash;

    my $admin_roles = [ $MediaWords::DBI::Auth::Roles::List::ADMIN, $MediaWords::DBI::Auth::Roles::List::ADMIN_READONLY ];

    $auth_users_id = int( $auth_users_id );

    my $is_admin = $db->query( <<SQL, @{ $admin_roles } )->hash;
select ar.role
    from auth_roles ar
        join auth_users_roles_map aurm using ( auth_roles_id )
    where
        aurm.auth_users_id = $auth_users_id and
        ar.role in ( ?? )
    limit 1
SQL

    # admins have no limit
    return if ( $is_admin );

    if ( $max_stories > $auth_user_limits->{ max_topic_stories } )
    {
        die( "max_stories ($max_stories ) is greater than allowed for user ($auth_user_limits->{ max_topic_stories })" );
    }
}

# return true if topics from this user should be put into the mc queue.  jobs should be put into the mc
# queue if the user has tm or any edit or admin roles
sub _is_mc_queue_user($$)
{
    my ( $db, $auth_users_id ) = @_;

    $auth_users_id = int( $auth_users_id );

    my $is_mc = $db->query(
        <<SQL,
select ar.role
    from auth_roles ar
        join auth_users_roles_map aurm using ( auth_roles_id )
    where
        aurm.auth_users_id = $auth_users_id and
        ar.role in ( ?? )
    limit 1
SQL
        @{ MediaWords::DBI::Auth::Roles::List::topic_mc_queue_roles() }
    )->hash;

    return $is_mc;
}

sub create : Local : ActionClass('MC_REST')
{
}

sub create_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    $self->require_fields( $c, [ qw/name description start_date end_date/ ] );

    my $data = $c->req->data;

    my $media_ids      = $data->{ media_ids }      || [];
    my $media_tags_ids = $data->{ media_tags_ids } || [];

    my $auth_users_id = $c->stash->{ api_auth }->user_id();

    _validate_max_stories( $db, $data->{ max_stories }, $auth_users_id );

    my $topic = { map { $_ => $data->{ $_ } } @{ $TOPICS_EDIT_FIELDS } };

    $topic->{ max_stories } ||= 100_000;
    $topic->{ is_logogram } ||= 0;
    $topic->{ platform }    ||= 'web';

    if ( $topic->{ solr_seed_query } )
    {
        eval
        {
            my $parser = MediaWords::Solr::Query::Parse::parse_solr_query( $topic->{ solr_seed_query } );
            $topic->{ pattern } = $parser->re( $topic->{ is_logogram } );
        };
        die( "unable to translate solr query to topic pattern: $@" ) if ( $@ );

        my $full_q = MediaWords::Solr::Query::get_full_solr_query_for_topic( $db, $topic, $media_ids, $media_tags_ids );
        my $num_stories = eval { MediaWords::Solr::get_solr_num_found( $db, $full_q ) };
        die( "invalid solr query: $@" ) if ( $@ );
    }

    $topic->{ is_public }            = normalize_boolean_for_db( $topic->{ is_public } );
    $topic->{ is_logogram }          = normalize_boolean_for_db( $topic->{ is_logogram } );
    $topic->{ is_story_index_ready } = normalize_boolean_for_db( $topic->{ is_story_index_ready } );
    $topic->{ solr_seed_query_run }  = normalize_boolean_for_db( $topic->{ solr_seed_query_run } );

    $topic->{ job_queue } = _is_mc_queue_user( $db, $auth_users_id ) ? 'mc' : 'public';

    $db->begin;

    $topic = $db->create( 'topics', $topic );

    _set_topic_media( $db, $topic, $media_ids, $media_tags_ids );

    $db->create(
        'topic_permissions',
        {
            topics_id     => $topic->{ topics_id },
            auth_users_id => $auth_users_id,
            permission    => 'admin'
        }
    );

    $db->commit;

    my $topics = _get_topics_list( $db, { topics_id => $topic->{ topics_id } }, $auth_users_id );

    $self->status_ok( $c, entity => { topics => $topics } );
}

# return true if the topic has any topic_stories with iteration > 1 and the update in $data removes
# media soures or dates from the query
sub _update_decreases_query_scope($$$)
{
    my ( $db, $topic, $data ) = @_;

    my $spidered_story = $db->query( <<SQL, $topic->{ topics_id } )->hash;
select * from topic_stories where iteration > 1 and topics_id = ? limit 1
SQL
    return 0 if ( !$spidered_story && $topic->{ state } ne 'running' );

    return 1 if ( $data->{ start_date } && ( $data->{ start_date } gt $topic->{ start_date } ) );

    return 1 if ( $data->{ end_date } && ( $data->{ end_date } lt $topic->{ end_date } ) );

    if ( my $update_media_ids = $data->{ media_ids } )
    {
        my $existing_media_ids = $db->query( <<SQL, $topic->{ topics_id } )->flat();
select media_id from topics_media_map where topics_id = ?
SQL

        for my $existing_id ( @{ $existing_media_ids } )
        {
            return 1 if ( !grep { $_ eq $existing_id } @{ $update_media_ids } );
        }
    }

    if ( my $update_media_tags_ids = $data->{ media_tags_ids } )
    {
        my $existing_media_tags_ids = $db->query( <<SQL, $topic->{ topics_id } )->flat;
select tags_id from topics_media_tags_map where topics_id = ?
SQL

        for my $existing_id ( @{ $existing_media_tags_ids } )
        {
            return 1 if ( !grep { $_ eq $existing_id } @{ $update_media_tags_ids } );
        }
    }

    return 0;
}

# if the query or dates have changed, set respider_stories in the topic to true so that the impacted
# stories will be respidered during the next spider job.
sub _set_stories_respidering($$$)
{
    my ( $db, $topic, $data ) = @_;

    if ( $data->{ solr_seed_query } && ( $topic->{ solr_seed_query } ne $data->{ solr_seed_query } ) )
    {
        $db->update_by_id( 'topics', $topic->{ topics_id }, { respider_stories => 't' } );
        return;
    }

    my $update_start_date = $data->{ start_date } || $topic->{ start_date };
    if ( $update_start_date ne $topic->{ start_date } )
    {
        $db->update_by_id(
            'topics',
            $topic->{ topics_id },
            { respider_stories => 't', respider_start_date => $topic->{ start_date } }
        );
    }

    my $update_end_date = $data->{ end_date } || $topic->{ end_date };
    if ( $update_end_date ne $topic->{ end_date } )
    {
        $db->update_by_id(
            'topics',
            $topic->{ topics_id },
            { respider_stories => 't', respider_end_date => $topic->{ end_date } }
        );
    }
}

sub add_seed_query : Chained( 'apibase' ) : ActionClass( 'MC_REST' )
{
}

sub add_seed_query_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', $c->stash->{ topics_id } );

    if ( $data->{ platform } eq 'postgres' )
    {
        die( "postgres source seed queries must be added manually." );
    }

    my $tsq = {
        topics_id => $topic->{ topics_id },
        platform  => $data->{ platform },
        source    => $data->{ source },
        query     => $data->{ query } . ''
    };

    $tsq = $db->find_or_create( 'topic_seed_queries', $tsq );

    $self->status_ok( $c, entity => { topic_seed_query => $tsq } );
}

sub remove_seed_query : Chained( 'apibase' ) : ActionClass( 'MC_REST' )
{
}

sub remove_seed_query_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', $c->stash->{ topics_id } );

    my $topic_seed_queries_id = $data->{ topic_seed_queries_id };

    die( "Must specify topic_seed_queries_id in input document" ) unless ( $topic_seed_queries_id );

    $db->delete_by_id( 'topic_seed_queries', $topic_seed_queries_id );

    $self->status_ok( $c, entity => { success => 1 } );
}

sub update : Chained( 'apibase' ) : ActionClass( 'MC_REST' )
{
}

sub update_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    my $media_ids      = $data->{ media_ids };
    my $media_tags_ids = $data->{ media_tags_ids };

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', $c->stash->{ topics_id } );

    my $update;
    for my $field ( @{ $TOPICS_EDIT_FIELDS } )
    {
        if ( defined( $data->{ $field } ) )
        {
            $update->{ $field } = $data->{ $field };
        }
    }

    if ( $update->{ solr_seed_query } && ( $topic->{ solr_seed_query } ne $update->{ solr_seed_query } ) )
    {
        my $is_logogram = defined( $update->{ is_logogram } ) ? $update->{ is_logogram } : $topic->{ is_logogram };
        $update->{ pattern } =
          eval { MediaWords::Solr::Query::Parse::parse_solr_query( $update->{ solr_seed_query } )->re( $is_logogram ) };
        die( "unable to translate solr query to topic pattern: $@" ) if ( $@ );

        $topic->{ solr_seed_query } = $update->{ solr_seed_query };

        my $full_solr_query = MediaWords::Solr::Query::get_full_solr_query_for_topic( $db, $topic, $media_ids, $media_tags_ids );
        my $num_stories = eval { MediaWords::Solr::get_solr_num_found( $db, $full_solr_query ) };
        die( "invalid solr query: $@" ) if ( $@ );
    }

    if ( _update_decreases_query_scope( $db, $topic, $data ) )
    {
        die( "topic update cannot reduce the scope of the query" );
    }

    $update->{ is_public }            = normalize_boolean_for_db( $update->{ is_public } );
    $update->{ is_logogram }          = normalize_boolean_for_db( $update->{ is_logogram } );
    $update->{ is_story_index_ready } = normalize_boolean_for_db( $update->{ is_story_index_ready } );
    $update->{ solr_seed_query_run }  = normalize_boolean_for_db( $update->{ solr_seed_query_run } );

    my $auth_users_id = $c->stash->{ api_auth }->user_id();

    _validate_max_stories( $db, $data->{ max_stories }, $auth_users_id ) if ( defined( $data->{ max_stories } ) );

    $db->begin;

    $db->update_by_id( 'topics', $topic->{ topics_id }, $update );

    _set_topic_media( $db, $topic, $media_ids, $media_tags_ids );

    _set_stories_respidering( $db, $topic, $data );

    $db->commit;

    my $topics = _get_topics_list( $db, { topics_id => $topic->{ topics_id } }, $auth_users_id );

    $self->status_ok( $c, entity => { topics => $topics } );
}

sub spider : Chained( 'apibase' ) : ActionClass( 'MC_REST' )
{
}

sub spider_GET
{
    my ( $self, $c ) = @_;

    my $topics_id = $c->stash->{ topics_id };

    my $data = $c->req->data;

    my $snapshots_id = $data->{ snapshots_id };

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', $topics_id );
    my $auth_users_id = $c->stash->{ api_auth }->user_id();

    # wrap this in a transaction so that we're sure the last job added is the one we just added
    $db->begin;

    my $mine_args = { topics_id => $topics_id, snapshots_id => $snapshots_id };

    my $queue_name = undef;
    if ( $topic->{ job_queue } eq 'mc' )
    {
        $queue_name = 'MediaWords::Job::TM::MineTopic';
    }
    elsif ( $topic->{ job_queue } eq 'public' )
    {
        $queue_name = 'MediaWords::Job::TM::MineTopicPublic';
    }
    else
    {
        LOGDIE( "unknown job_queue type: $topic->{ job_queue }" );
    }

    MediaWords::Job::StatefulBroker->new( $queue_name )->add_to_queue( $mine_args );

    my $job_state = $db->query( "select $JOB_STATE_FIELD_LIST from job_states order by job_states_id desc limit 1" )->hash;

    $db->commit;

    die( "Unable to find job state from queued job" ) unless ( $job_state );

    return $self->status_ok( $c, entity => { job_state => $job_state } );
}

sub spider_status : Chained( 'apibase' ) : ActionClass( 'MC_REST' )
{
}

sub spider_status_GET
{
    my ( $self, $c ) = @_;

    my $topics_id = $c->stash->{ topics_id };

    my $db = $c->dbis;

    my $job_states = $db->query( <<SQL,
        SELECT $JOB_STATE_FIELD_LIST
        FROM job_states
        WHERE
            class LIKE 'MediaWords::Job::TM::MineTopic%' AND
            (args->>'topics_id')::BIGINT = \$1
        ORDER BY last_updated DESC
SQL
        $topics_id
    )->hashes;

    $self->status_ok( $c, entity => { job_states => $job_states } );
}

sub reset : Chained( 'apibase' ) : ActionClass( 'MC_REST' )
{
}

sub reset_PUT
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id = int( $c->stash->{ topics_id } );

    my $topic = $db->require_by_id( 'topics', $topics_id );

    if ( $topic->{ state } eq 'running' )
    {
        die( "Cannot reset running topic." );
    }

    $db->query( "delete from topic_stories where topics_id = ?",                   $topics_id );
    $db->query( "delete from topic_links where topics_id = ?",                     $topics_id );
    $db->query( "delete from topic_dead_links where topics_id = ?",                $topics_id );
    $db->query( "delete from topic_seed_urls where topics_id = ?",                 $topics_id );
    $db->query( "update topics set solr_seed_query_run = 'f' where topics_id = ?", $topics_id );

    $db->update_by_id( 'topics', $topic->{ topics_id }, { state => 'created but not queued', message => undef } );

    $self->status_ok( $c, entity => { success => 1 } );
}

sub info : Local : ActionClass('MC_REST')
{
}

sub info_GET 
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $info = {};

    $info->{ topic_modes } = $db->query( "select * from topic_modes order by name" )->hashes;
    $info->{ topic_platforms } = $db->query( "select * from topic_platforms order by name" )->hashes;
    $info->{ topic_sources } = $db->query( "select * from topic_sources order by name" )->hashes;
    $info->{ topic_platforms_sources_map } = $db->query( <<SQL )->hashes;
select 
        tp.topic_platforms_id,
        tp.name platform_name,
        tp.description platform_description,
        ts.topic_sources_id,
        ts.name source_name,
        ts.description source_description
    from topic_platforms tp
        join topic_platforms_sources_map tpsm using ( topic_platforms_id )
        join topic_sources ts using ( topic_sources_id )
    order by ts.name, tp.name
SQL

    $self->status_ok( $c, entity => { info => $info } );

}

sub list_timespan_files : Chained( 'apibase' ) : ActionClass( 'MC_REST' )
{

}

sub list_timespan_files_GET
{
    my ( $self, $c ) = @_;

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    my $timespan = MediaWords::DBI::Timespans::set_timespans_id_param( $c );

    my $timespan_files = $db->query( <<SQL, $timespan->{ timespans_id } )->hashes;
select * from timespan_files where timespans_id = ? order by timespan_files_id
SQL

    $self->status_ok( $c, entity => { timespan_files => $timespan_files } );
}

sub list_snapshot_files : Chained( 'apibase' ) : ActionClass( 'MC_REST' )
{

}

sub list_snapshot_files_GET
{
    my ( $self, $c ) = @_;

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    my $timespan = MediaWords::DBI::Timespans::set_timespans_id_param( $c );

    my $snapshot_files = $db->query( <<SQL, $timespan->{ snapshots_id } )->hashes;
select * from snapshot_files where snapshots_id = ? order by snapshot_files_id
SQL

    $self->status_ok( $c, entity => { snapshot_files => $snapshot_files } );
}

1;
