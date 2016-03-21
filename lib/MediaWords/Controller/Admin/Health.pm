package MediaWords::Controller::Admin::Health;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME>

MediaWords::Controller::Health - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller for media source health pages.

=cut

sub index : Path : Args(0)
{
    return list( @_ );
}

# get the tags.* fields with the following health data attached:
# num_media, num_sentences(_y/90/w), num_healthy, num_active_feeds
#
# param should be either { tags_id => $id } or { tag_sets_id => $id }
sub _get_tag_stats
{
    my ( $db, $params ) = @_;

    my ( $tag_clause, $tag_id );
    if ( my $id = $params->{ tags_id } )
    {
        ( $tag_clause, $tag_id ) = ( "t.tags_id = ?", $id );
    }
    elsif ( $id = $params->{ tag_sets_id } )
    {
        ( $tag_clause, $tag_id ) = ( "t.tag_sets_id = ?", $id );
    }
    else
    {
        die( "Unrecognized param: " . Dumper( $params ) );
    }

    my $tags = $db->query( <<SQL, $tag_id )->hashes;
select t.*,
        sum( num_stories ) num_stories,
        sum( num_sentences ) num_sentences,
        sum( num_stories_w ) num_stories_w,
        sum( num_sentences_w ) num_sentences_w,
        sum( num_stories_90 ) num_stories_90,
        sum( num_sentences_90 ) num_sentences_90,
        sum( num_stories_y ) num_stories_y,
        sum( num_sentences_y ) num_sentences_y,
        sum( case when is_healthy then 1 else 0 end ) num_healthy,
        sum( case when has_active_feed then 1 else 0 end ) num_active_feeds,
        count( * ) num_media
    from media_health mh
        join media_tags_map mtm on ( mtm.media_id = mh.media_id )
        join tags t on ( mtm.tags_id = t.tags_id )
    where
        $tag_clause
    group by t.tags_id
    order by num_stories_90 desc
SQL

    return $tags;
}

# assign aggregate health data about the media sources associated with the tag.
# assigns the following fields to the tag: media, num_media, num_sentences(_y/90/w),
# num_healthy, num_active_feeds
sub _assign_health_data_to_tag
{
    my ( $db, $tag ) = @_;

    my $media = $db->query( <<SQL, $tag->{ tags_id } )->hashes;
select m.*, mh.*
    from media m
        join media_tags_map mtm on ( mtm.media_id = m.media_id )
        left join media_health mh on ( mh.media_id = m.media_id )
    where
        mtm.tags_id = ?
SQL

    $tag->{ media } = $media;

    my $tags = _get_tag_stats( $db, { tags_id => $tag->{ tags_id } } );
    my $stats = $tags->[ 0 ];

    map { $tag->{ $_ } = $stats->{ $_ } } keys( %{ $stats } );
}

# get tag_sets_id for collection: tag set
sub _get_collection_tag_sets_id
{
    my ( $db ) = @_;

    my $tag_set = $db->query( "select * from tag_sets where name = 'collection'" )->hash
      || die( "Unable to find 'collection' tag set" );

    return $tag_set->{ tag_sets_id };
}

# list the overall health of each tag in a tag_set
sub list : Local
{
    my ( $self, $c, $tag_sets_id ) = @_;

    my $db = $c->dbis;

    $tag_sets_id ||= _get_collection_tag_sets_id( $db );

    my $tag_set = $db->find_by_id( 'tag_sets', $tag_sets_id )
      || die( "Unable to find tag set '$tag_sets_id'" );

    my $tags = _get_tag_stats( $db, { tag_sets_id => $tag_sets_id } );

    $c->stash->{ tags }     = $tags;
    $c->stash->{ tag_set }  = $tag_set;
    $c->stash->{ template } = 'health/list.tt2';
}

# list tag sets
sub tag_sets : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $tag_sets = $db->query( <<END )->hashes;
select ts.*
    from tag_sets ts
    where
        exists (
            select 1
                from media_tags_map mtm
                    join tags t on ( mtm.tags_id = t.tags_id )
                where t.tag_sets_id = ts.tag_sets_id
        )
    order by name
END

    $c->stash->{ tag_sets } = $tag_sets;
    $c->stash->{ template } = 'health/tag_sets.tt2';
}

# list the media sources in the given tag, with health info for each
sub tag : Local
{
    my ( $self, $c, $tags_id ) = @_;

    my $db = $c->dbis;

    my $tag = $db->find_by_id( 'tags', $tags_id ) || die( "unknown tag '$tags_id'" );

    _assign_health_data_to_tag( $db, $tag );

    $c->stash->{ tag }      = $tag;
    $c->stash->{ template } = 'health/tag.tt2';
}

# display daily health stats for the given media source
sub medium : Local
{
    my ( $self, $c, $media_id ) = @_;

    my $db = $c->dbis;

    $db->find_by_id( 'media', $media_id ) || die( "unknown medium '$media_id'" );

    my $medium = $db->query( <<SQL, $media_id )->hash;
select m.*, mh.* from media m join media_health mh on ( m.media_id = mh.media_id ) where m.media_id = ?
SQL

    my $media_stats = $db->query( <<SQL, $media_id )->hashes;
select ms.*
    from media_stats ms
    where
        ms.media_id = ?
    order by stat_date desc
SQL

    $c->stash->{ 'medium' }      = $medium;
    $c->stash->{ 'media_stats' } = $media_stats;
    $c->stash->{ 'template' }    = 'health/medium.tt2';
}

sub stories : Local
{
    my ( $self, $c, $media_id ) = @_;

    my $db = $c->dbis;

    my $medium = $db->find_by_id( 'media', $media_id ) || die( "unknown medium '$media_id'" );

    my $date = $c->req->params->{ date } || die( "missing date" );

    my $stories = $db->query( <<END, $media_id, $date )->hashes;
with media_stories as (
    select s.*, d.downloads_id
        from stories s
            join downloads d on ( d.stories_id = s.stories_id )
        where media_id = \$1 and date_trunc( 'day', publish_date ) = \$2
)

select s.*,
    coalesce( ss_ag.num_sentences, 0 ) num_sentences,
    coalesce( dt_ag.text_length, 0 ) text_length

    from media_stories s

        left join
            ( select ss.stories_id, count(*) num_sentences
                from story_sentences ss
                where ss.stories_id in
                    ( select stories_id from media_stories )
                group by ss.stories_id ) ss_ag on ( s.stories_id = ss_ag.stories_id )

        left join
            ( select ms.stories_id, sum( dt.download_text_length ) text_length
                from media_stories ms
                    join download_texts dt on ( ms.downloads_id = dt.downloads_id )
                group by ms.stories_id ) dt_ag on ( s.stories_id = dt_ag.stories_id )

    order by publish_date
END

    $c->stash->{ medium }   = $medium;
    $c->stash->{ date }     = $date;
    $c->stash->{ stories }  = $stories;
    $c->stash->{ template } = 'health/stories.tt2';
}

1;
