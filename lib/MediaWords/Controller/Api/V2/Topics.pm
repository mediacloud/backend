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

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    action => {
        list   => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        single => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        create => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
        update => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
    }
);

Readonly my $TOPICS_EDIT_FIELDS =>
  [ qw/name solr_seed_query description max_iterations start_date end_date is_public ch_monitor_id twitter_topics_id/ ];

sub _get_topics_list($$$)
{
    my ( $db, $params, $auth_users_id ) = @_;

    my $name = $params->{ name } || '';
    my $topics_id = $params->{ topics_id };

    my $limit  = $params->{ limit };
    my $offset = $params->{ offset };

    my $id_clause = '';
    if ( $topics_id )
    {
        $id_clause = 't.topics_id = ' . int( $topics_id ) . ' and ';
    }

    my $topics = $db->query( <<END, $auth_users_id, $name, $limit, $offset )->hashes;
select t.topics_id, t.name, t.pattern, t.solr_seed_query, t.description, t.max_iterations, t.state,
        t.error_message, t.is_public, t.ch_monitor_id, t.twitter_topics_id, t.start_date, t.end_date,
        min( p.auth_users_id ) auth_users_id, min( p.user_permission ) user_permission
    from topics t
        join topics_with_user_permission p using ( topics_id )
        left join snapshots snap on ( t.topics_id = snap.topics_id )
    where
        $id_clause
        p.auth_users_id= \$1 and
        t.name like '%' || \$2 || '%'
    group by t.topics_id
    order by t.state = 'completed successfully', t.state,  max( coalesce( snap.snapshot_date, '2000-01-01'::date ) ) desc
    limit \$3 offset \$4
END

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

    my $auth_users_id = $c->stash->{ api_auth }->{ auth_users_id };

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

    my $auth_users_id = $c->stash->{ api_auth }->{ auth_users_id };

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

sub create : Local : ActionClass('MC_REST')
{
}

sub create_GET
{
    my ( $self, $c ) = @_;

    $self->require_fields( $c, [ qw/name solr_seed_query description start_date end_date/ ] );

    my $data = $c->req->data;

    my $media_ids      = $data->{ media_ids }      || [];
    my $media_tags_ids = $data->{ media_tags_ids } || [];

    if ( !( scalar( @{ $media_ids } ) || scalar( @{ $media_tags_ids } ) ) )
    {
        die( "must include either media_ids or mmedia_tags_ids" );
    }

    my $topic = { map { $_ => $data->{ $_ } } @{ $TOPICS_EDIT_FIELDS } };

    $topic->{ pattern } = eval { MediaWords::Solr::Query::parse( $topic->{ solr_seed_query } )->re() };
    die( "unable to translate solr query to topic pattern: $@" ) if ( $@ );

    my $db = $c->dbis;

    my $full_solr_query = MediaWords::TM::Mine::get_full_solr_query( $db, $topic, $media_ids, $media_tags_ids );
    my $num_stories = eval { MediaWords::Solr::count_stories( $db, { q => $full_solr_query } ) };
    die( "invalid solr query: $@" ) if ( $@ );

    die( "number of stories from query ($num_stories) is more than the max (500,000)" ) if ( $num_stories > 500000 );

    $db->begin;

    $topic = $db->create( 'topics', $topic );

    _set_topic_media( $db, $topic, $media_ids, $media_tags_ids );

    my $auth_users_id = $c->stash->{ api_auth }->{ auth_users_id };

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

sub update : Local : ActionClass('MC_REST')
{
}

sub update_PUT
{
    my ( $self, $c ) = @_;

    $self->require_fields( $c, [ 'topics_id' ] );

    my $data = $c->req->data;

    my $media_ids      = $data->{ media_ids };
    my $media_tags_ids = $data->{ media_tags_ids };

    if ( $media_ids && $media_tags_ids && !( scalar( @{ $media_ids } ) || scalar( @{ $media_tags_ids } ) ) )
    {
        die( "media_ids and media_tags_ids cannot both be empty" );
    }

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', $data->{ topics_id } );

    my $update = { map { $_ => $data->{ $_ } } @{ $TOPICS_EDIT_FIELDS } };

    if ( $update->{ solr_seed_query } && ( $topic->{ solr_seed_query } ne $update->{ solr_seed_query } ) )
    {
        $update->{ pattern } = eval { MediaWords::Solr::Query::parse( $update->{ solr_seed_query } )->re() };
        die( "unable to translate solr query to topic pattern: $@" ) if ( $@ );

        my $full_solr_query = MediaWords::TM::Mine::get_full_solr_query( $db, $topic, $media_ids, $media_tags_ids );
        my $num_stories = eval { MediaWords::Solr::count_stories( $db, { q => $full_solr_query } ) };
        die( "invalid solr query: $@" ) if ( $@ );

        die( "number of stories from query ($num_stories) is more than the max (500,000)" ) if ( $num_stories > 500000 );
    }

    $db->begin;

    $db->update_by_id( 'topics', $topic->{ topics_id }, $update );

    _set_topic_media( $db, $topic, $media_ids, $media_tags_ids );

    $db->commit;

    my $auth_users_id = $c->stash->{ api_auth }->{ auth_users_id };

    my $topics = _get_topics_list( $db, { topics_id => $topic->{ topics_id } }, $auth_users_id );

    $self->status_ok( $c, entity => { topics => $topics } );
}

1;
