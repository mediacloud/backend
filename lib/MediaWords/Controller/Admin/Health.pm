package MediaWords::Controller::Admin::Health;

use Modern::Perl "2013";
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

# get the status of the given period by checking whether period $i
# is less than 10% (red) or 50% (yellow) of any subsequent period
# for any of num_stories, num_sentences, num_stories_with_text, or
# num_stories_with_sentences
sub _get_health_status
{
    my ( $stats, $i ) = @_;
    
    my $status = 'green';
    
    my $a = $stats->[ $i ];
    for ( my $j = $i + 1; $j < @{ $stats }; $j++ )
    {
        my $b = $stats->[ $j ];
        for my $k ( qw/num_stories num_sentences num_stories_with_text num_stories_with_sentences/ )
        {
            next unless ( $b->{ $k } );

            my $a_value = $a->{ $k } || 1;
            my $b_value = $b->{ $k };
            
            if ( ( $a_value / $b_value ) < 0.10 )
            {
                return 'red';
            }
            elsif ( ( $a_value / $b_value ) < 0.25 )
            {
                $status = 'yellow';
            }
        }
    }
    
    return $status;
}

# assign health data to the media source as the following stats
sub _assign_health_data_to_medium
{
    my ( $db, $medium ) = @_;
    
    my $medium_stats = $db->query( <<END, $medium->{ media_id } )->hashes;
select * from media_stats
    where media_id = ? and stat_date < now() - interval '1 day'
    order by stat_date desc
END

    $medium->{ media_stats } ||= [];

    for my $ms ( @{ $medium_stats } )
    {
        push( @{ $medium->{ media_stats } }, $ms );
        
        my $fields = [ qw/num_stories num_sentences num_stories_with_sentences num_stories_with_text/ ];
        map { $medium->{ $_ } += $ms->{ $_ } || 0 } @{ $fields };
    }
    
    my $media_stats = $medium->{ media_stats };
    for ( my $i = 0; $i < @{ $media_stats }; $i++ )
    {
        $media_stats->[ $i ]->{ status } = _get_health_status( $media_stats, $i );
    }
    
    $medium->{ status } = $media_stats->[ 0 ]->{ status } || '';    
}

# assign aggregate health data about the media sources associated with the tag.
# assigns the following fields to the tag: media, num_stories, num_sentences, num_stories_with_sentences,
# num_stories_with_text, num_media, num_healthy_media, percent_health_media
sub _assign_health_data_to_tag
{
    my ( $db, $tag ) = @_;
    
    my $media = $db->query( <<END, $tag->{ tags_id } )->hashes;
select m.* 
    from media m join media_tags_map mtm on ( m.media_id = mtm.media_id ) 
    where mtm.tags_id = ?
    order by m.media_id
END

    for my $medium ( @{ $media } )
    {
        _assign_health_data_to_medium( $db, $medium );

        my $fields = [ qw/num_stories num_sentences num_stories_with_sentences num_stories_with_text/ ];
        map { $tag->{ $_ } += $medium->{ $_ } || 0 } @{ $fields };
    }
    
    $tag->{ media } = $media;
    $tag->{ num_media } = scalar( @{ $media } );
    
    $tag->{ num_healthy_media } = scalar( grep { $_->{ status } ne 'red' } @{ $media } );
    if ( $tag->{ num_media } )
    {
        $tag->{ percent_healthy_media } = int( 100 * ( $tag->{ num_healthy_media } / $tag->{ num_media } ) );
    }
    else {
        $tag->{ percent_healthy_media } = 'na';
    }

}

# find any media set and dashboard associated with the tag and
# add the corresponding media_set_name and dashboard_name fields
sub _assign_media_set_to_tag
{
    my ( $db, $tag ) = @_;
    
    my $media_sets = $db->query( <<END, $tag->{ tags_id } )->hashes;
select ms.*, d.name dashboard_name
    from media_sets ms
        join dashboard_media_sets dms on ( dms.media_sets_id = ms.media_sets_id )
        join dashboards d on ( d.dashboards_id = dms.dashboards_id ) 
    where
        ms.tags_id = ?
END

   
   $tag->{ media_set_names } = join( '; ', map { "$_->{ dashboard_name }:$_->{ name }" } @{ $media_sets } );
}

# list the overall health of each collection: tag
sub list : Local
{
    my ( $self, $c, $media_id ) = @_;
    
    my $db = $c->dbis;
    
    my $tags = $db->query( <<END )->hashes;
with collection_tags as (
    
    select t.* 
        from tags t 
            join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
        where ts.name = 'collection'
)
        
select t.*, s.*,
        media_set_names
    from collection_tags t
    
        left join (
            select 
                mtm.tags_id,
                count( distinct mtm.media_id ) num_media,
                ( sum( 
                    case when ms.stat_date > now() - interval '1 month' 
                        then 1 
                        else 0 end ) * 100 / count(*) )::int percent_current_media,
                sum( ms.num_stories ) num_stories,
                sum( ms.num_stories_with_text ) num_stories_with_text,
                sum( ms.num_sentences ) num_sentences,
                sum( ms.num_stories_with_sentences ) num_stories_with_sentences
            from 
                media_tags_map mtm
                    left join media_stats ms on ( ms.media_id = mtm.media_id )
            group by mtm.tags_id
            
        ) s on ( t.tags_id = s.tags_id )
        
        left join (
            select ms.tags_id,
                array_to_string( array_agg( d.name || ':' || ms.name ), '; ' ) media_set_names
            from media_sets ms
                join dashboard_media_sets dms on ( dms.media_sets_id = ms.media_sets_id )
                join dashboards d on ( d.dashboards_id = dms.dashboards_id ) 
            where ms.tags_id is not null
            group by ms.tags_id
        ) ms on ( t.tags_id = ms.tags_id )

    order by media_set_names, t.tags_id
END

    for my $tag ( @{ $tags } )
    {
        # _assign_health_data_to_tag( $db, $tag );
        _assign_media_set_to_tag( $db, $tag );
    }
    
    $c->stash->{ tags } = $tags;
    $c->stash->{ template } = 'health/list.tt2';
}

# list the media sources in the given tag, with health info for each
sub tag : Local
{
    my ( $self, $c, $tags_id ) = @_;
    
    my $db = $c->dbis;
    
    my $tag = $db->find_by_id( 'tags', $tags_id ) || die( "unknown tag '$tags_id'" );
    
    _assign_health_data_to_tag( $db, $tag );
    _assign_media_set_to_tag( $db, $tag );
    
    $c->stash->{ tag } = $tag;
    $c->stash->{ template } = 'health/tag.tt2';
}

# display daily health stats for the given media source
sub medium : Local
{
    my ( $self, $c, $media_id ) = @_;
    
    my $db = $c->dbis;
    
    my $medium = $db->find_by_id( 'media', $media_id ) || die( "unknown medium '$media_id'" );
    
    _assign_health_data_to_medium( $db, $medium );
    
    $c->stash->{ 'medium' } = $medium;
    $c->stash->{ 'template' } = 'health/medium.tt2';
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

    $c->stash->{ medium } = $medium;
    $c->stash->{ date } = $date;
    $c->stash->{ stories } = $stories;
    $c->stash->{ template } = 'health/stories.tt2';
}

1;
