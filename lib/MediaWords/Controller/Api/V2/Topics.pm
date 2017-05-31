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

use MediaWords::TM::Mine;

BEGIN
{
    extends 'MediaWords::Controller::Api::V2::MC_Controller_REST';
    use MediaWords::DBI::Auth::Roles;
}

__PACKAGE__->config(
    action => {
        list          => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        single        => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        create        => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        update        => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
        spider        => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
        spider_status => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

Readonly::Scalar my $TOPICS_EDIT_FIELDS => [
    qw/name solr_seed_query description max_iterations start_date end_date is_public ch_monitor_id twitter_topics_id max_stories/
];

Readonly::Scalar my $JOB_STATE_FIELD_LIST =>
  "job_states_id, ( args->>'topics_id' )::int topics_id, state, message, last_updated";

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
        <<END,
select t.topics_id, t.name, t.pattern, t.solr_seed_query, t.solr_seed_query_run,
        t.description, t.max_iterations, t.state,
        t.message, t.is_public, t.ch_monitor_id, t.twitter_topics_id, t.start_date, t.end_date,
        min( p.auth_users_id ) auth_users_id, min( p.user_permission ) user_permission,
        t.job_queue, t.max_stories
    from topics t
        join topics_with_user_permission p using ( topics_id )
        left join snapshots snap on ( t.topics_id = snap.topics_id )
    where
        $id_clause
        $public_clause
        p.auth_users_id= \$1 and
        t.name like \$2 and
        p.user_permission <> 'none'
    group by t.topics_id
    order by t.state = 'completed', t.state,  max( coalesce( snap.snapshot_date, '2000-01-01'::date ) ) desc
    limit \$3 offset \$4
END
        $auth_users_id, '%' . $name . '%', $limit, $offset
    )->hashes;

    $topics = $db->attach_child_query( $topics, <<SQL, 'media', 'topics_id' );
select m.media_id, m.name, tmm.topics_id
    from media m join topics_media_map tmm using ( media_id )
SQL

    $topics = $db->attach_child_query( $topics, <<SQL, 'media_tags', 'topics_id' );
select t.tags_id, t.tag, t.label, t.description, tmtm.topics_id
    from tags t join topics_media_tags_map tmtm using ( tags_id )
SQL

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

    my $auth_users_id = $c->stash->{ api_auth }->id();

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

    my $auth_users_id = $c->stash->{ api_auth }->id();

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

    if ( $max_stories > $auth_user->{ max_topic_stories } )
    {
        die( "max_stories ($max_stories ) is greater than allowed for user ($auth_user->{ max_topic_stories })" );
    }
}

# return true if topics from this user should be put into the mc queue.  jobs should be put into the mc
# queue if the user has tm or any edit or admin roles
sub _is_mc_queue_user($$)
{
    my ( $db, $auth_users_id ) = @_;

    $auth_users_id = int( $auth_users_id );

    my $is_mc = $db->query( <<SQL, @{ $MediaWords::DBI::Auth::Roles::List::TOPIC_MC_QUEUE_ROLES } )->hash;
select ar.role
    from auth_roles ar
        join auth_users_roles_map aurm using ( auth_roles_id )
    where
        aurm.auth_users_id = $auth_users_id and
        ar.role in ( ?? )
    limit 1
SQL

    return $is_mc;
}

sub create : Local : ActionClass('MC_REST')
{
}

sub create_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    $self->require_fields( $c, [ qw/name solr_seed_query description start_date end_date/ ] );

    my $data = $c->req->data;

    my $media_ids      = $data->{ media_ids }      || [];
    my $media_tags_ids = $data->{ media_tags_ids } || [];

    my $auth_users_id = $c->stash->{ api_auth }->id();

    _validate_max_stories( $db, $data->{ max_stories }, $auth_users_id );
    $data->{ max_stories } ||= 100_000;

    if ( !( scalar( @{ $media_ids } ) || scalar( @{ $media_tags_ids } ) ) )
    {
        die( "must include either media_ids or mmedia_tags_ids" );
    }

    my $topic = { map { $_ => $data->{ $_ } } @{ $TOPICS_EDIT_FIELDS } };

    $topic->{ pattern } = eval { MediaWords::Solr::Query::parse( $topic->{ solr_seed_query } )->re() };
    die( "unable to translate solr query to topic pattern: $@" ) if ( $@ );

    $topic->{ is_public }           = normalize_boolean_for_db( $topic->{ is_public } );
    $topic->{ solr_seed_query_run } = normalize_boolean_for_db( $topic->{ solr_seed_query_run } );

    my $full_solr_query = MediaWords::TM::Mine::get_full_solr_query( $db, $topic, $media_ids, $media_tags_ids );
    my $num_stories = eval { MediaWords::Solr::count_stories( $db, { q => $full_solr_query } ) };
    die( "invalid solr query: $@" ) if ( $@ );

    die( "number of stories from query ($num_stories) is more than the max (500,000)" ) if ( $num_stories > 500000 );

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

# sub stories : Chained('apibase') : PathPart('stories') : CaptureArgs(0)
# sub list : Chained('stories') : Args(0) : ActionClass('MC_REST')

sub update : Chained( 'apibase' ) : ActionClass( 'MC_REST' )
{
}

sub update_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    my $media_ids      = $data->{ media_ids };
    my $media_tags_ids = $data->{ media_tags_ids };

    if ( $media_ids && $media_tags_ids && !( scalar( @{ $media_ids } ) || scalar( @{ $media_tags_ids } ) ) )
    {
        die( "media_ids and media_tags_ids cannot both be empty" );
    }

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
        $update->{ pattern } = eval { MediaWords::Solr::Query::parse( $update->{ solr_seed_query } )->re() };
        die( "unable to translate solr query to topic pattern: $@" ) if ( $@ );

        my $full_solr_query = MediaWords::TM::Mine::get_full_solr_query( $db, $topic, $media_ids, $media_tags_ids );
        my $num_stories = eval { MediaWords::Solr::count_stories( $db, { q => $full_solr_query } ) };
        die( "invalid solr query: $@" ) if ( $@ );

        die( "number of stories from query ($num_stories) is more than the max (500,000)" ) if ( $num_stories > 500000 );
    }

    $update->{ is_public }           = normalize_boolean_for_db( $update->{ is_public } );
    $update->{ solr_seed_query_run } = normalize_boolean_for_db( $update->{ solr_seed_query_run } );

    my $auth_users_id = $c->stash->{ api_auth }->id();

    _validate_max_stories( $db, $data->{ max_stories }, $auth_users_id ) if ( defined( $data->{ max_stories } ) );

    $db->begin;

    $db->update_by_id( 'topics', $topic->{ topics_id }, $update );

    _set_topic_media( $db, $topic, $media_ids, $media_tags_ids );

    $db->commit;

    my $topics = _get_topics_list( $db, { topics_id => $topic->{ topics_id } }, $auth_users_id );

    $self->status_ok( $c, entity => { topics => $topics } );
}

# return a pending job states for MineTopicPublic for this user if one exists
sub _get_user_public_queued_job($$)
{
    my ( $db, $auth_users_id ) = @_;

    my $job_state = $db->query( <<SQL, $auth_users_id )->hash;
select $JOB_STATE_FIELD_LIST
    from pending_job_states pjs
        join topic_permissions tp on ( ( pjs.args->>'topics_id' )::int = tp.topics_id )
    where
        class like 'MediaWords::Job::TM::MineTopic%' and
        tp.permission in ( 'admin', 'write' ) and
        tp.auth_users_id = ?
    order by job_states_id desc
SQL

    return $job_state;
}

sub spider : Chained( 'apibase' ) : ActionClass( 'MC_REST' )
{
}

sub spider_GET
{
    my ( $self, $c ) = @_;

    my $topics_id = $c->stash->{ topics_id };

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', $topics_id );
    my $auth_users_id = $c->stash->{ api_auth }->id();

    if ( my $job_state = _get_user_public_queued_job( $db, $auth_users_id ) )
    {
        return $self->status_ok( $c, entity => { job_state => $job_state } );
    }

    my $job_state = $db->query( <<SQL, $topics_id )->hash;
select $JOB_STATE_FIELD_LIST
    from pending_job_states
    where
        ( args->>'topics_id' )::int = \$1 and
        class like 'MediaWords::Job::TM::MineTopic%'
    order by job_states_id desc
SQL

    if ( !$job_state )
    {
        # wrap this in a transaction so that we're sure the last job added is the one we just added
        $db->begin;

        MediaWords::TM::add_to_mine_job_queue( $db, $topic );
        $job_state = $db->query( "select $JOB_STATE_FIELD_LIST from job_states order by job_states_id desc limit 1" )->hash;

        $db->commit;

        die( "Unable to find job state from queued job" ) unless ( $job_state );
    }

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

    my $job_states = $db->query( <<SQL, $topics_id )->hashes;
select $JOB_STATE_FIELD_LIST
    from job_states
    where
        class like 'MediaWords::Job::TM::MineTopic%' and
        ( args->>'topics_id' )::int = \$1
    order by last_updated desc
SQL

    $self->status_ok( $c, entity => { job_states => $job_states } );
}

1;
