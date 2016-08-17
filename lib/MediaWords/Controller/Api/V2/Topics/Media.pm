package MediaWords::Controller::Api::V2::Topics::Media;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;

use MediaWords::DBI::ApiLinks;
use MediaWords::Solr;
use MediaWords::TM::Snapshot;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list_GET => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;
    $c->stash->{ topics_id } = $topics_id;
}

sub media : Chained('apibase') : PathPart('media') : CaptureArgs(0)
{

}

sub list : Chained('media') : Args(0) : ActionClass('MC_REST')
{

}

# if topic_timespans_id is specified, create a temporary
# table with the media name that supercedes the normal media table
# but includes only media in the given topic timespan and
# has the topic metric data
sub _create_topic_media_table
{
    my ( $self, $c, $timespans_id ) = @_;

    # my $timespan_mode = $c->req->params->{ topic_mode } || '';

    return unless ( $timespans_id );

    $self->{ topic_media } = 1;

    # my $live = $timespan_mode eq 'live' ? 1 : 0;

    my $db = $c->dbis;

    my $timespan = $db->find_by_id( 'timespans', $timespans_id )
      || die( "Unable to find timespan with id '$timespans_id'" );

    my $topic = $db->query( <<END, $timespan->{ snapshots_id } )->hash;
select * from topics where topics_id in (
    select topics_id from snapshots where snapshots_id = ? )
END

    $db->begin;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, 0 );

    $db->query( <<END );
create temporary table media as
    select m.name, m.url, mlc.*
        from snapshot_media m join snapshot_medium_link_counts mlc on ( m.media_id = mlc.media_id )
END

    $db->commit;
}

# get any where clauses for media_id, link_to_stories_id, link_from_stories_id, stories_id params
sub _get_extra_where_clause($$)
{
    my ( $c, $timespans_id ) = @_;

    my $clauses = [];

    if ( my $media_id = $c->req->params->{ media_id } )
    {
        $media_id += 0;
        push( @{ $clauses }, "m.media_id = $media_id" );
    }

    if ( my $name = $c->req->params->{ name } )
    {
        if ( length( $name ) < 3 )
        {
            push( @{ $clauses }, "false" );
        }
        else
        {
            my $q_name_val = $c->dbis->dbh->quote( $name );
            push( @{ $clauses }, "m.name ilike '%' || $q_name_val || '%'" );
        }
    }

    return '' unless ( @{ $clauses } );

    return 'and ' . join( ' and ', map { "( $_ ) " } @{ $clauses } );
}

sub list_GET : Local
{
    my ( $self, $c ) = @_;

    my $timespan = MediaWords::TM::set_timespans_id_param( $c );

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    my $sort_param = $c->req->params->{ sort } || 'inlink';

    # md5 hashing is to make tie breaks random but consistent
    my $sort_clause =
      ( $sort_param eq 'social' )
      ? 'mlc.bitly_click_count desc nulls last, md5( m.media_id::text )'
      : 'mlc.media_inlink_count desc, md5( m.media_id::text )';

    my $timespans_id = $timespan->{ timespans_id };
    my $snapshots_id = $timespan->{ snapshots_id };

    my $limit  = $c->req->params->{ limit };
    my $offset = $c->req->params->{ offset };

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

    my $entity = { media => $media };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'media' );

    $self->status_ok( $c, entity => $entity );
}

1;
