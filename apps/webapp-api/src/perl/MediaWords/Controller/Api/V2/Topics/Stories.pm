package MediaWords::Controller::Api::V2::Topics::Stories;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use Readonly;

use MediaWords::DBI::ApiLinks;
use MediaWords::Solr;
use MediaWords::DBI::Snapshots;
use MediaWords::DBI::Timespans;
use MediaWords::DBI::Stories::GuessDate;

Readonly my $DEFAULT_STORY_LIMIT => 10;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    action => {
        list     => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        links    => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        facebook => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        count    => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub link_paging_key { return 'stories'; }

sub pre_deserialize($$)
{
    my ( $self, $c ) = @_;

    $c->stash->{ timespan } = MediaWords::DBI::Timespans::set_timespans_id_param( $c );
}

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;

    $c->stash->{ topics_id } = $topics_id;
}

sub stories : Chained('apibase') : PathPart('stories') : CaptureArgs(0)
{
}

sub links : Chained('stories') : Args(0) : ActionClass('MC_REST')
{
}

sub links_GET
{
    my ( $self, $c ) = @_;

    my $timespan = MediaWords::DBI::Timespans::set_timespans_id_param( $c );

    my $db = $c->dbis;

    $c->req->params->{ limit } = List::Util::min( int( $c->req->params->{ limit } // 1_000 ), 1_000 );
    my $limit = $c->req->params->{ limit };

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $offset = int( $c->req->params->{ offset } // 0 );

    my $topics_id = $timespan->{ topics_id };
    my $timespans_id = $timespan->{ timespans_id };
    my $snapshots_id = $timespan->{ snapshots_id };

    my $links = $db->query( <<SQL,
        SELECT
            source_stories_id,
            ref_stories_id
        FROM snap.story_links
        WHERE
            topics_id = ? AND
            timespans_id = ?
        ORDER BY
            source_stories_id,
            ref_stories_id
        LIMIT ?
        OFFSET ?
SQL
        $topics_id, $timespans_id, $limit, $offset
    )->hashes;

    my $entity = { links => $links };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'links' );

    $self->status_ok( $c, entity => $entity );
}

sub list : Chained('stories') : Args(0) : ActionClass('MC_REST')
{
}

# get any where clauses for media_id, link_to_stories_id, link_from_stories_id, stories_id params
sub _get_extra_where_clause($$$)
{
    my ( $c, $topics_id, $timespans_id ) = @_;

    $topics_id = int( $topics_id );
    $timespans_id = int( $timespans_id );

    my $clauses = [];

    if ( my $media_id = $c->req->params->{ media_id } )
    {
        my $media_ids = ref( $media_id ) ? $media_id : [ $media_id ];
        my $media_ids_list = join( ',', map { int( $_ ) } @{ $media_ids } ) || '-1';
        push( @{ $clauses }, <<SQL
            EXISTS (
                SELECT s.stories_id
                FROM snap.stories AS s
                    INNER JOIN timespans AS t ON
                        s.topics_id = t.topics_id AND
                        s.snapshots_id = t.snapshots_id
                WHERE
                    s.topics_id = $topics_id AND
                    t.timespans_id = $timespans_id AND
                    s.media_id in ($media_ids_list) AND
                    s.stories_id = slc.stories_id
            )
SQL
        );
    }

    if ( my $stories_id = $c->req->params->{ stories_id } )
    {
        my $stories_ids = ref( $stories_id ) ? $stories_id : [ $stories_id ];
        my $stories_ids_list = join( ',', map { int( $_ ) } @{ $stories_ids } ) || '-1';
        push( @{ $clauses }, "slc.stories_id IN ($stories_ids_list)" );
    }

    if ( my $link_to_stories_id = int( $c->req->params->{ link_to_stories_id } // 0 ) )
    {
        push( @{ $clauses }, <<SQL
            slc.stories_id IN (
                SELECT sl.source_stories_id
                FROM snap.story_links sl
                WHERE
                    sl.ref_stories_id = $link_to_stories_id AND
                    sl.topics_id = $topics_id AND
                    sl.timespans_id = $timespans_id
            )
SQL
        );
    }

    if ( my $link_from_stories_id = int( $c->req->params->{ link_from_stories_id } // 0 ) )
    {
        push( @{ $clauses }, <<SQL
            slc.stories_id IN (
                SELECT sl.ref_stories_id
                FROM snap.story_links AS sl
                WHERE
                    sl.source_stories_id = $link_from_stories_id AND
                    sl.topics_id = $topics_id AND
                    sl.timespans_id = $timespans_id
            )
SQL
        );
    }

    if ( my $link_to_media_id = int( $c->req->params->{ link_to_media_id } // 0 ) )
    {
        push( @{ $clauses }, <<SQL
            slc.stories_id IN (
                SELECT sl.source_stories_id
                FROM snap.story_links AS sl
                    INNER JOIN timespans AS t ON
                        sl.topics_id = t.topics_id AND
                        sl.timespans_id = t.timespans_id
                    INNER JOIN snap.stories AS s ON
                        sl.topics_id = s.topics_id AND
                        sl.ref_stories_id = s.stories_id AND
                        s.snapshots_id = t.snapshots_id
                WHERE
                    s.media_id = $link_to_media_id AND
                    sl.topics_id = $topics_id AND
                    sl.timespans_id = $timespans_id
            )
SQL
        );

    }

    if ( my $link_from_media_id = int( $c->req->params->{ link_from_media_id } // 0 ) )
    {
        push( @{ $clauses }, <<SQL
            slc.stories_id IN (
                SELECT sl.ref_stories_id
                FROM snap.story_links AS sl
                    INNER JOIN timespans AS t ON
                        sl.topics_id = t.topics_id AND
                        sl.timespans_id = t.timespans_id
                    INNER JOIN snap.stories AS s ON
                        sl.topics_id = s.topics_id AND
                        sl.source_stories_id = s.stories_id AND
                        s.snapshots_id = t.snapshots_id
                WHERE
                    s.media_id = $link_from_media_id AND
                    sl.topics_id = $topics_id AND
                    sl.timespans_id = $timespans_id
            )
SQL
        );
    }

    if ( my $q = $c->req->params->{ q } )
    {
        $q = "timespans_id:$timespans_id and ( $q )";

        my $solr_stories_id = MediaWords::Solr::search_solr_for_stories_ids(
            $c->dbis,
            {
                'q' => $q,
                'rows' => 10_000_000,
            }
        );

        $solr_stories_id = [ map { int( $_ ) } @{ $solr_stories_id } ];

        my $ids_table = $c->dbis->get_temporary_ids_table( $solr_stories_id );
        push( @{ $clauses }, "slc.stories_id IN (SELECT id FROM $ids_table)" );
    }

    return '' unless ( @{ $clauses } );

    return 'and ' . join( ' and ', map { "( $_ ) " } @{ $clauses } );
}

# add a foci list to each story that lists each focus to which the story belongs
sub _add_foci_to_stories($$$)
{
    my ( $db, $timespan, $stories ) = @_;

	my $foci = MediaWords::DBI::Snapshots::get_story_foci( $db, $timespan, $stories );

    $stories = MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $foci, 'foci' );

    return $stories;
}

# add post/author/comment counts to each story for each seed query
sub _add_url_sharing_counts_to_stories($$$)
{
    my ( $db, $timespan, $stories ) = @_;

	my $counts = MediaWords::DBI::Snapshots::get_story_counts( $db, $timespan, $stories );

    $stories = MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $counts, 'url_sharing_counts' );

	return $stories;
}

# accept sort_param of inlink, facebook, or twitter and
# return a sort clause for the story_link_counts table, aliased as 'slc',
# that will sort by the relevant field
sub _get_sort_clause
{
    my ( $sort_param ) = @_;

    $sort_param ||= 'inlink';

    my $sort_field_lookup = {
        inlink       => 'slc.media_inlink_count DESC',
        inlink_count => 'slc.media_inlink_count DESC',
        facebook     => 'slc.facebook_share_count DESC NULLS LAST',
        twitter      => 'slc.post_count DESC NULLS LAST',
        post_count  => 'slc.post_count DESC NULLS LAST',
        author_count  => 'slc.author_count DESC NULLS LAST',
        channel_count  => 'slc.channel_count DESC NULLS LAST',
        random       => 'RANDOM()'
    };

    my $sort_field = $sort_field_lookup->{ lc( $sort_param ) }
      || die( "unknown sort value: '$sort_param'" );

    return $sort_field;
}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $timespan = MediaWords::DBI::Timespans::set_timespans_id_param( $c );

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    $c->req->params->{ sort } ||= 'inlink';

    my $sort_clause = _get_sort_clause( $c->req->params->{ sort } );
    $sort_clause = "ORDER BY slc.timespans_id DESC, $sort_clause, MD5(slc.stories_id::text) DESC";

    my $topics_id = $timespan->{ topics_id };
    my $timespans_id = $timespan->{ timespans_id };
    my $snapshots_id = $timespan->{ snapshots_id };

    my $extra_clause = _get_extra_where_clause( $c, $topics_id, $timespans_id );

    my $offset = int( $c->req->params->{ offset } // 0 );

    $c->req->params->{ limit } = List::Util::min( int( $c->req->params->{ limit } // 1_000 ), 1_000_000 );
    my $limit = $c->req->params->{ limit };

    my $pre_limit_order = $extra_clause ? '' : "$sort_clause LIMIT $limit OFFSET $offset";
    my $post_limit_offset =  $extra_clause ? "OFFSET $offset" : '';

    my $stories = $db->query( <<"SQL",

        WITH _topics_stories_slc AS (
            SELECT *
            FROM snap.story_link_counts AS slc
            WHERE
                topics_id = \$1 AND
                timespans_id = \$2
                $extra_clause
            $pre_limit_order
        )

        SELECT
            s.*,
            slc.*,
            m.name AS media_name
        FROM _topics_stories_slc AS slc
            INNER JOIN snap.stories AS s ON
                slc.topics_id = s.topics_id AND
                slc.stories_id = s.stories_id AND
                s.snapshots_id = \$3
            INNER JOIN snap.media AS m ON
                s.topics_id = m.topics_id AND
                s.media_id = m.media_id AND
                m.snapshots_id = \$3
        
        $sort_clause

	    LIMIT $limit
        $post_limit_offset

SQL
        $topics_id, $timespans_id, $snapshots_id
    )->hashes;

    $stories = _add_foci_to_stories( $db, $timespan, $stories );
    $stories = _add_url_sharing_counts_to_stories( $db, $timespan, $stories );

    MediaWords::DBI::Stories::GuessDate::add_date_is_reliable_to_stories( $db, $stories );

    MediaWords::DBI::Stories::GuessDate::add_undateable_to_stories( $db, $stories );
    map { $_->{ publish_date } = 'undateable' if ( $_->{ undateable } ); delete( $_->{ undateable } ) } @{ $stories };

    map { $_->{ stories_id } = int( $_->{ stories_id } ) } @{ $stories };

    my $entity = { stories => $stories };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'stories' );

    $self->status_ok( $c, entity => $entity );

}

sub facebook : Chained('stories') : Args(0) : ActionClass('MC_REST')
{
}

sub facebook_GET
{
    my ( $self, $c ) = @_;

    my $timespan = MediaWords::DBI::Timespans::set_timespans_id_param( $c );

    my $db = $c->dbis;

    $c->req->params->{ limit } = int( $c->req->params->{ limit } // 1000 );

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $topics_id = $timespan->{ topics_id };
    my $timespans_id = $timespan->{ timespans_id };

    my $limit  = int( $c->req->params->{ limit }  // 0 );
    my $offset = int( $c->req->params->{ offset } // 0 );

    my $counts = $db->query( <<SQL,
        WITH snapshot_story_ids AS (
            SELECT stories_id
            FROM snap.story_link_counts
            WHERE
                topics_id = \$1 AND
                timespans_id = \$2
        )

        SELECT
            stories_id,
            facebook_share_count,
            facebook_comment_count,
            facebook_api_collect_date
        FROM story_statistics
        WHERE stories_id IN (
            SELECT stories_id
            FROM snapshot_story_ids
        )
        ORDER BY stories_id
        LIMIT \$3
        OFFSET \$4
SQL
        $topics_id, $timespans_id, $limit, $offset
    )->hashes;

    my $entity = { counts => $counts };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'counts' );

    $self->status_ok( $c, entity => $entity );

}

sub count : Chained('stories') : Args(0) : ActionClass('MC_REST')
{
}

sub count_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $timespan = MediaWords::DBI::Timespans::require_timespan_for_topic(
        $c->dbis,
        $c->stash->{ topics_id },
        int( $c->req->params->{ timespans_id } // 0 ),
        int( $c->req->params->{ snapshots_id } // 0 )
    );

    my $q = $c->req->params->{ q };

    my $timespan_clause = "timespans_id:$timespan->{ timespans_id }";

    $q = $q ? "$timespan_clause AND ($q)" : $timespan_clause;

    $c->req->params->{ q } = $q;

    $c->req->params->{ split_start_date } ||= substr( $timespan->{ start_date }, 0, 12 );
    $c->req->params->{ split_end_date }   ||= substr( $timespan->{ end_date },   0, 12 );

    return $c->controller( 'Api::V2::Stories_Public' )->count_GET( $c );

}

1;
