package MediaWords::Controller::Api::V2::Topics::Media;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;

use MediaWords::DBI::ApiLinks;
use MediaWords::DBI::Snapshots;
use MediaWords::DBI::Timespans;
use MediaWords::Solr;
use MediaWords::TM::Snapshot::GEXF;
use MediaWords::TM::Snapshot::Views;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    action => {
        links => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        list  => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        map   => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        list_maps   => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;
    $c->stash->{ topics_id } = int( $topics_id );
}

sub media : Chained('apibase') : PathPart('media') : CaptureArgs(0)
{

}

sub list : Chained('media') : Args(0) : ActionClass('MC_REST')
{

}

# get any where clauses for media_id, link_to_stories_id, link_from_stories_id, stories_id params
sub _get_extra_where_clause($$)
{
    my ( $c, $timespans_id ) = @_;

    my $clauses = [];

    if ( my $media_ids = $c->req->params->{ media_id } )
    {
        $media_ids = [ $media_ids ] unless ( ref( $media_ids ) eq ref( [] ) );
        my $media_ids_list = join( ',', map { int( $_ ) } @{ $media_ids } );
        push( @{ $clauses }, "m.media_id in ( $media_ids_list )" );
    }

    if ( my $q = $c->req->params->{ q } )
    {
        $q = "timespans_id:$timespans_id and ( $q )";
        my $media_ids = MediaWords::Solr::search_solr_for_media_ids( $c->dbis, { q => $q } );
        my $media_ids_list = join( ',', map { int( $_ ) } ( @{ $media_ids }, -1 ) );
        push( @{ $clauses }, "m.media_id in ( $media_ids_list )" );
    }

    if ( my $name = $c->req->params->{ name } )
    {
        if ( length( $name ) < 3 )
        {
            push( @{ $clauses }, "false" );
        }
        else
        {
            my $q_name_val = $c->dbis->quote( '%' . $name . '%' );
            push( @{ $clauses }, "m.name ilike $q_name_val" );
        }
    }

    return '' unless ( @{ $clauses } );

    return 'and ' . join( ' and ', map { "( $_ ) " } @{ $clauses } );
}

# accept sort_param of inlink, facebook, or twitter and
# return a sort clause for the medium_link_counts table, aliased as 'mlc',
# that will sort by the relevant field
sub _get_sort_clause
{
    my ( $sort_param ) = @_;

    $sort_param ||= 'inlink';

    my $sort_field_lookup = {
        inlink       => 'mlc.media_inlink_count',
        inlink_count => 'mlc.media_inlink_count',
        facebook     => 'mlc.facebook_share_count',
        twitter      => 'mlc.sum_post_count',
        sum_post_count  => 'mlc.sum_post_count',
        sum_author_count  => 'mlc.sum_author_count',
        sum_channel_count  => 'mlc.sum_channel_count'
    };

    my $sort_field = $sort_field_lookup->{ lc( $sort_param ) }
      || die( "unknown sort value: '$sort_param'" );

    # md5 hashing is to make tie breaks random but consistent
    return "$sort_field desc nulls last, md5( mlc.media_id::text )";
}

# given a list of media, add associated tags to each using a single postgres query.
# add the list of tags to each medium using the 'media_source_tags' field.
sub _add_tags_to_media($$)
{
    my ( $db, $media ) = @_;

    my $media_ids_list = join( ',', map { $_->{ media_id } } @{ $media } ) || '-1';
    my $tags = $db->query( <<END )->hashes;
select mtm.media_id, t.tags_id, t.tag, t.label, t.description, mtm.tagged_date, ts.tag_sets_id, ts.name as tag_set,
        ( t.show_on_media or ts.show_on_media ) show_on_media,
        ( t.show_on_stories or ts.show_on_stories ) show_on_stories
    from media_tags_map mtm
        join tags t on ( mtm.tags_id = t.tags_id )
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where mtm.media_id in ( $media_ids_list )
    order by t.tags_id
END

    my $tags_lookup = {};
    map { push( @{ $tags_lookup->{ $_->{ media_id } } }, $_ ) } @{ $tags };
    map { $_->{ media_source_tags } = $tags_lookup->{ $_->{ media_id } } || [] } @{ $media };
}

# add url sharing counts to the media
sub _add_counts_to_media($$$)
{
    my ( $db, $timespan, $media ) = @_;

    my $counts = MediaWords::DBI::Snapshots::get_medium_counts( $db, $timespan, $media );

    my $tags_lookup = {};
    map { push( @{ $tags_lookup->{ $_->{ media_id } } }, $_ ) } @{ $counts };
    map { $_->{ url_sharing_counts } = $tags_lookup->{ $_->{ media_id } } || [] } @{ $media };
}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $timespan = MediaWords::DBI::Timespans::set_timespans_id_param( $c );

    $c->req->params->{ limit } = int( List::Util::min( $c->req->params->{ limit } // 0, 1_000 ) );

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    my $sort_param = $c->req->params->{ sort } || 'inlink';

    my $sort_clause = _get_sort_clause( $c->req->params->{ sort } );

    my $timespans_id = $timespan->{ timespans_id };
    my $snapshots_id = $timespan->{ snapshots_id };

    my $limit = int( $c->req->params->{ limit } );
    my $offset = int( $c->req->params->{ offset } // 0 );

    my $extra_clause = _get_extra_where_clause( $c, $timespans_id );

    my $media = $db->query( <<SQL, $timespans_id, $snapshots_id, $limit, $offset )->hashes;
select *
    from snap.medium_link_counts mlc
        join snap.media m on mlc.media_id = m.media_id
    where mlc.timespans_id = \$1 and
        m.snapshots_id = \$2
        $extra_clause
    order by $sort_clause
    limit \$3 offset \$4

SQL

    _add_tags_to_media( $db, $media );
    _add_counts_to_media( $db, $timespan, $media );

    my $entity = { media => $media };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'media' );

    $self->status_ok( $c, entity => $entity );
}

sub links : Chained('media') : Args(0) : ActionClass('MC_REST')
{
}

sub links_GET
{
    my ( $self, $c ) = @_;

    my $timespan = MediaWords::DBI::Timespans::set_timespans_id_param( $c );

    $c->req->params->{ limit } = int( List::Util::min( $c->req->params->{ limit } // 1_000, 1_000_000 ) );
    my $limit = $c->req->params->{ limit };

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    my $offset = int( $c->req->params->{ offset } // 0 );

    my $timespans_id = $timespan->{ timespans_id };
    my $snapshots_id = $timespan->{ snapshots_id };

    my $links = $db->query( <<SQL, $timespans_id, $limit, $offset )->hashes;
select source_media_id, ref_media_id from snap.medium_links
    where timespans_id = ?
    order by source_media_id, ref_media_id
    limit ? offset ?
SQL

    my $entity = { links => $links };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'links' );

    $self->status_ok( $c, entity => $entity );
}

sub _new_map
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $timespan = MediaWords::DBI::Timespans::set_timespans_id_param( $c );

    my $timespan_maps_id = $c->req->params->{ timespan_maps_id };
    my $format = $c->req->params->{ format };

    my $map;
    if ( $timespan_maps_id )
    {
        $map = $db->require_by_id( 'timespan_maps', $timespan_maps_id );
    }
    else
    {
        $map = $db->query( <<SQL, $timespan->{ timespans_id }, $format )->hash;
select * from timespan_maps where timespans_id = ? and format = ?
SQL
        die( "no maps found for timespan $timespan->{ timespans_id } with format $format" ) unless $map;
    }


    my $types = {
        gexf => 'text/gexf; charset=UTF-8',
        svg => 'image/svg'
    };

    my $content_type = $types->{ $format };

    die( "unknown format: $format" ) unless $content_type;

    my $filename = "topic_map_$map->{ timespan_maps_id }.$format";

    $c->response->header( "Content-Disposition" => "attachment;filename=$filename" );
    $c->response->content_type( $content_type );
    $c->response->body( $map->{ content } );
}

sub map : Chained('media') : Args(0) : ActionClass('MC_REST')
{

}

sub map_GET
{
    my ( $self, $c ) = @_;



    if ( $c->req->params->{ format } || $c->req->params->{ timespan_maps_id } )
    {
        return $self->_new_map( $c );
    }

    my $timespan = MediaWords::DBI::Timespans::set_timespans_id_param( $c );

    my $color_field          = $c->req->params->{ color_field } || 'media_type';
    my $num_media            = int( $c->req->params->{ num_media } // 500 );
    my $include_weights      = int( $c->req->params->{ include_weights } // 0 );
    my $num_links_per_medium = int( $c->req->params->{ num_links_per_medium } // 1000 );
    my $exclude_media_ids    = $c->req->params->{ exclude_media_ids } || [];

    unless ( ref( $exclude_media_ids ) eq ref( [] ) )
    {
        $exclude_media_ids = [ $exclude_media_ids ];
    }

    $exclude_media_ids = [ map { int( $_ ) } @{ $exclude_media_ids } ];

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', int( $c->stash->{ topics_id } ) );

    MediaWords::TM::Snapshot::Views::setup_temporary_snapshot_views( $db, $timespan );

    my $gexf_options = {
        max_media            => $num_media,
        color_field          => $color_field,
        include_weights      => $include_weights,
        max_links_per_medium => $num_links_per_medium,
        exclude_media_ids    => $exclude_media_ids
    };
    my $gexf = MediaWords::TM::Snapshot::GEXF::get_gexf_snapshot( $db, $timespan, $gexf_options );

    MediaWords::TM::Snapshot::Views::discard_temp_tables_and_views( $db );

    my $file = "media_$timespan->{ timespans_id }.gexf";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/gexf; charset=UTF-8' );
    $c->response->content_length( bytes::length( $gexf ) );
    $c->response->body( $gexf );
}

sub list_maps : Chained('media') : Args(0) : ActionClass('MC_REST')
{
}

sub list_maps_GET
{
    my ( $self, $c ) = @_;

    my $timespan = MediaWords::DBI::Timespans::set_timespans_id_param( $c );

    my $db = $c->dbis;

    my $timespan_maps = $db->query( <<SQL, $timespan->{ timespans_id } )->hashes;
select timespan_maps_id, timespans_id, options, format, url, length(content) content_length
    from timespan_maps
    where timespans_id = ?
    order by timespans_id
SQL

    $self->status_ok( $c, entity => { timespan_maps => $timespan_maps } );
}

1;
