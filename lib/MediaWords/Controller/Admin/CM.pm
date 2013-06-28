package MediaWords::Controller::Admin::CM;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;
use warnings;
use parent 'Catalyst::Controller';

use List::Compare;

sub index : Path : Args(0)
{

    return list( @_ );
}

# list all controversies
sub list : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $controversies = $db->query( <<END )->hashes;
select * from controversies_with_search_info order by controversies_id desc
END

    $c->stash->{ controversies } = $controversies;
    $c->stash->{ template }      = 'cm/list.tt2';
}

# add a periods field to the controversy dump
sub _add_periods_to_controversy_dump
{
    my ( $db, $controversy_dump ) = @_;

    my $periods = $db->query( <<END, $controversy_dump->{ controversy_dumps_id } )->hashes;
select distinct period from controversy_dump_time_slices
    where controversy_dumps_id = ?
    order by period;
END

    $controversy_dump->{ periods } = join( ", ", map { $_->{ period } } @{ $periods } );
}

# view the details of a single controversy
sub view : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $db = $c->dbis;

    my $controversy = $db->query( <<END, $controversies_id )->hash;
select * from controversies_with_search_info where controversies_id = ?
END

    my $query = MediaWords::DBI::Queries::find_query_by_id( $db, $controversy->{ queries_id } );
    $query->{ media_set_names } = MediaWords::DBI::Queries::get_media_set_names( $db, $query ) if ( $query );

    my $controversy_dumps = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select * from controversy_dumps where controversies_id = ?
    order by controversy_dumps_id desc
END

    map { _add_periods_to_controversy_dump( $db, $_ ) } @{ $controversy_dumps };

    $c->stash->{ controversy }       = $controversy;
    $c->stash->{ query }             = $query;
    $c->stash->{ controversy_dumps } = $controversy_dumps;
    $c->stash->{ template }          = 'cm/view.tt2';
}

# add num_stories, num_story_links, num_media, and num_media_links
# fields to the controversy_dump_time_slice
sub _add_media_and_story_counts_to_cdts
{
    my ( $db, $cdts ) = @_;

    ( $cdts->{ num_stories } ) = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->flat;
select count(*) from cd.story_link_counts where controversy_dump_time_slices_id = ?
END

    ( $cdts->{ num_story_links } ) = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->flat;
select count(*) from cd.story_links where controversy_dump_time_slices_id = ?
END

    ( $cdts->{ num_media } ) = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->flat;
select count(*) from cd.medium_link_counts where controversy_dump_time_slices_id = ?
END

    ( $cdts->{ num_medium_links } ) = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->flat;
select count(*) from cd.medium_links where controversy_dump_time_slices_id = ?
END
}

# view a controversy dump, with a list of its time slices
sub view_dump : Local
{
    my ( $self, $c, $controversy_dumps_id ) = @_;

    my $db = $c->dbis;

    my $controversy_dump = $db->query( <<END, $controversy_dumps_id )->hash;
select * from controversy_dumps where controversy_dumps_id = ?
END

    my $controversy_dump_time_slices = $db->query( <<END, $controversy_dumps_id )->hashes;
select * from controversy_dump_time_slices 
    where controversy_dumps_id = ? 
    order by period, start_date, end_date
END

    map { _add_media_and_story_counts_to_cdts( $db, $_ ) } @{ $controversy_dump_time_slices };

    $c->stash->{ controversy_dump }             = $controversy_dump;
    $c->stash->{ controversy_dump_time_slices } = $controversy_dump_time_slices;
    $c->stash->{ template }                     = 'cm/view_dump.tt2';
}

# view timelices, with links to csv and gexf files
sub view_time_slice : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    my $db = $c->dbis;

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $controversy_dump_time_slices_id );

    _add_media_and_story_counts_to_cdts( $db, $cdts );

    $c->stash->{ cdts }     = $cdts;
    $c->stash->{ template } = 'cm/view_time_slice.tt2';
}

# download a csv field from controversy_dump_time_slices_id
sub _download_cdts_csv
{
    my ( $c, $controversy_dump_time_slices_id, $csv ) = @_;

    my $field = $csv . '_csv';

    my $db = $c->dbis;

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $controversy_dump_time_slices_id );

    my $file = "${ csv }_$cdts->{ controversy_dump_time_slices_id }.csv";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/csv; charset=UTF-8' );
    $c->response->content_length( bytes::length( $cdts->{ $field } ) );
    $c->response->body( $cdts->{ $field } );
}

# download the stories_csv for the given time slice
sub dump_stories : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'stories' );
}

# download the story_links_csv for the given time slice
sub dump_story_links : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'story_links' );
}

# download the media_csv for the given time slice
sub dump_media : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'media' );
}

# download the medium_links_csv for the given time slice
sub dump_medium_links : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'medium_links' );
}

# download the gexf file for the time slice
sub gexf : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id, $csv ) = @_;

    my $db = $c->dbis;

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $controversy_dump_time_slices_id );

    my $gexf = $cdts->{ gexf };

    my $base_url = $c->uri_for( '/' );

    $gexf =~ s/\[_mc_base_url_\]/$base_url/g;

    my $file = "media_$cdts->{ controversy_dump_time_slices_id }.gexf";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/gexf; charset=UTF-8' );
    $c->response->content_length( bytes::length( $gexf ) );
    $c->response->body( $gexf );
}

# download a csv field from controversy_dumps
sub _download_cd_csv
{
    my ( $c, $controversy_dumps_id, $csv ) = @_;

    my $field = $csv . '_csv';

    my $db = $c->dbis;

    my $cd = $db->find_by_id( 'controversy_dumps', $controversy_dumps_id );

    my $file = "${ csv }_$cd->{ controversy_dumps_id }.csv";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/csv; charset=UTF-8' );
    $c->response->content_length( bytes::length( $cd->{ $field } ) );
    $c->response->body( $cd->{ $field } );
}

# download the daily_counts_csv for the given dump
sub dump_daily_counts : Local
{
    my ( $self, $c, $controversy_dumps_id ) = @_;

    _download_cd_csv( $c, $controversy_dumps_id, 'daily_counts' );
}

# download the weekly_counts_csv for the given dump
sub dump_weekly_counts : Local
{
    my ( $self, $c, $controversy_dumps_id ) = @_;

    _download_cd_csv( $c, $controversy_dumps_id, 'weekly_counts' );
}

# return the latest dump if it is not the dump to which the cdts belongs.  otherwise return undef.
sub _get_latest_controversy_dump
{
    my ( $db, $cdts ) = @_;

    my $latest_dump = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->hash;
select latest.* from controversy_dumps latest, controversy_dumps current, controversy_dump_time_slices cdts
    where cdts.controversy_dump_time_slices_id = ? and
        current.controversy_dumps_id = cdts.controversy_dumps_id and
        latest.controversy_dumps_id > current.controversy_dumps_id and
        latest.controversies_id = current.controversies_id
    order by latest.controversy_dumps_id desc 
    limit 1
END

    return $latest_dump;
}

# get data about the medium as it existed in the given time slice.  include medium_stories,
# inlink_stories, and outlink_stories from the time slice as well.
sub _get_cdts_medium_and_stories
{
    my ( $db, $cdts, $media_id ) = @_;

    my $cdts_id = $cdts->{ controversy_dump_time_slices_id };

    my $medium = $db->query( <<END, $cdts_id, $media_id )->hash;
select m.*, mlc.inlink_count, mlc.outlink_count, mlc.story_count
    from cd.media m, cd.medium_link_counts mlc, controversy_dump_time_slices cdts
    where m.media_id = mlc.media_id and
        cdts.controversy_dump_time_slices_id = ? and
        m.media_id = ? and
        mlc.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id and
        m.controversy_dumps_id = cdts.controversy_dumps_id
END

    $medium->{ stories } = $db->query( <<END, $cdts_id, $media_id )->hashes;
select s.*, slc.inlink_count, slc.outlink_count, m.name medium_name
    from cd.stories s, cd.story_link_counts slc, controversy_dump_time_slices cdts, cd.media m
    where s.stories_id = slc.stories_id and
        cdts.controversy_dump_time_slices_id = ? and
        s.media_id = ? and
        s.controversy_dumps_id = cdts.controversy_dumps_id and
        slc.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id and
        m.media_id = s.media_id and
        m.controversy_dumps_id = cdts.controversy_dumps_id
    order by slc.inlink_count desc
END

    $medium->{ inlink_stories } = $db->query( <<'END', $media_id, $cdts_id )->hashes;
select a.*, q.story_count, m.name medium_name, slc.inlink_count, slc.outlink_count
    from cd.stories a, cd.media m, cd.story_link_counts slc, 
        ( select cdts.controversy_dumps_id, s.stories_id, count(*) story_count
            from cd.stories s, cd.stories r, 
                cd.controversy_links_cross_media cl, controversy_dump_time_slices cdts
            where s.stories_id = cl.stories_id and
                cl.ref_stories_id = r.stories_id and
                r.media_id = $1 and
                cdts.controversy_dump_time_slices_id = $2 and
                s.controversy_dumps_id = cdts.controversy_dumps_id and
                r.controversy_dumps_id = cdts.controversy_dumps_id
            group by cdts.controversy_dumps_id, s.stories_id
        ) q
    where q.stories_id = a.stories_id and
        a.controversy_dumps_id = q.controversy_dumps_id and
        a.media_id = m.media_id and
        m.controversy_dumps_id = q.controversy_dumps_id and
        slc.stories_id = q.stories_id and
        slc.controversy_dump_time_slices_id = $2
    order by slc.inlink_count desc
END

    $medium->{ outlink_stories } = $db->query( <<'END', $media_id, $cdts_id )->hashes;
select a.*, q.story_count, m.name medium_name, slc.inlink_count, slc.outlink_count
    from cd.stories a, cd.media m, cd.story_link_counts slc, 
        ( select cdts.controversy_dumps_id, r.stories_id, count(*) story_count
            from cd.stories s, cd.stories r, 
                cd.controversy_links_cross_media cl, controversy_dump_time_slices cdts
            where s.stories_id = cl.stories_id and
                cl.ref_stories_id = r.stories_id and
                s.media_id = $1 and
                cdts.controversy_dump_time_slices_id = $2 and
                s.controversy_dumps_id = cdts.controversy_dumps_id and
                r.controversy_dumps_id = cdts.controversy_dumps_id
            group by cdts.controversy_dumps_id, r.stories_id
        ) q
    where q.stories_id = a.stories_id and
        a.controversy_dumps_id = q.controversy_dumps_id and
        a.media_id = m.media_id and
        m.controversy_dumps_id = q.controversy_dumps_id and
        slc.stories_id = q.stories_id and 
        slc.controversy_dump_time_slices_id = $2
    order by slc.inlink_count desc
END

    return $medium;
}

# get live data about the medium within the given controversy.  Include medium_stories,
# inlink_stories, and outlink_stories.
sub _get_live_medium_and_stories
{
    my ( $db, $controversy, $media_id ) = @_;

    my $c_id = $controversy->{ controversies_id };

    my $medium = $db->find_by_id( 'media', $media_id );

    $db->begin;

    # cache a few tables that we use repeatedly below;
    $db->query( <<END, $c_id );
create temporary table cached_controversy_links_cross_media on commit drop as 
    select * from controversy_links_cross_media
        where controversies_id = ?
END

    $db->query( <<'END' );
create temporary table cached_story_link_counts on commit drop as
    select csa.stories_id, coalesce( ilc.inlink_count, 0 ) inlink_count, 
            coalesce( olc.outlink_count, 0 ) outlink_count
        from controversy_stories csa 
            left join 
                ( select cl.ref_stories_id, count(*) inlink_count 
                    from cached_controversy_links_cross_media cl
                    group by cl.ref_stories_id ) ilc on ( csa.stories_id = ilc.ref_stories_id )
            left join 
                ( select cl.stories_id, count(*) outlink_count 
                    from cached_controversy_links_cross_media cl
                    group by cl.stories_id ) olc on ( csa.stories_id = olc.stories_id )
END

    $medium->{ stories } = $db->query( <<'END', $c_id, $media_id )->hashes;
select s.*, m.name medium_name, slc.inlink_count, slc.outlink_count
    from stories s, controversy_stories cs, media m, cached_story_link_counts slc
    where s.stories_id = cs.stories_id and
        s.stories_id = slc.stories_id and
        s.media_id = m.media_id and
        cs.controversies_id = $1 and
        s.media_id = $2 
    order by slc.inlink_count desc
END

    $medium->{ inlink_stories } = $db->query( <<'END', $media_id, $c_id )->hashes;
select s.*, sm.name medium_name, slc.inlink_count, slc.outlink_count
    from stories s, media sm, stories r, cached_controversy_links_cross_media cl,
        cached_story_link_counts slc
    where 
        s.media_id = sm.media_id and
        s.stories_id = cl.stories_id and
        r.stories_id = cl.ref_stories_id and
        s.stories_id = slc.stories_id and
        r.media_id = ? and
        cl.controversies_id = ?
    order by slc.inlink_count desc
END

    $medium->{ outlink_stories } = $db->query( <<'END', $media_id, $c_id )->hashes;
select r.*, rm.name medium_name, slc.inlink_count, slc.outlink_count
    from stories s, stories r, media rm, cached_controversy_links_cross_media cl,
        cached_story_link_counts slc
    where 
        r.media_id = rm.media_id and
        s.stories_id = cl.stories_id and
        r.stories_id = cl.ref_stories_id and
        s.stories_id = slc.stories_id and
        s.media_id = ? and
        cl.controversies_id = ?
    order by slc.inlink_count desc
END

    $medium->{ story_count }   = scalar( @{ $medium->{ stories } } );
    $medium->{ inlink_count }  = scalar( @{ $medium->{ inlink_stories } } );
    $medium->{ outlink_count } = scalar( @{ $medium->{ outlink_stories } } );

    # commit to drop the temp tables
    $db->commit;

    return $medium;
}

# view live data for medium
sub live_medium : Local
{
    my ( $self, $c, $controversies_id, $media_id ) = @_;

    my $db = $c->dbis;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id );

    my $medium = _get_live_medium_and_stories( $db, $controversy, $media_id );

    $c->stash->{ controversy } = $controversy;
    $c->stash->{ medium }      = $medium;
    $c->stash->{ template }    = 'cm/medium.tt2';
}

# check each of the following for differences between the live and dump medium:
# * name
# * url
# * ids of stories
# * ids of inlink_stories
# * ids of outlink_stories
#
# return undef if there are no diffs and otherwise a string list of the
# attributes (above) for which there are differences
sub _get_live_medium_diffs
{
    my ( $dump_medium, $live_medium ) = @_;

    my $live_medium_diffs = [];

    for my $field ( qw(name url) )
    {
        push( @{ $live_medium_diffs }, $field ) if ( $dump_medium->{ $field } ne $live_medium->{ $field } );
    }

    for my $list ( qw(stories inlink_stories outlink_stories) )
    {
        my $live_ids = [ map { $_->{ stories_id } } @{ $live_medium->{ $list } } ];
        my $dump_ids = [ map { $_->{ stories_id } } @{ $dump_medium->{ $list } } ];

        my $lc = List::Compare->new( $live_ids, $dump_ids );
        if ( !$lc->is_LequivalentR() )
        {
            my $list_name = $list;
            $list_name =~ s/_/ /g;
            push( @{ $live_medium_diffs }, $list_name );
        }
    }

    return ( @{ $live_medium_diffs } ) ? join( ", ", @{ $live_medium_diffs } ) : undef;
}

# view medium as it existed at the time of the dump
sub medium : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id, $media_id ) = @_;

    my $db = $c->dbis;

    my $cdts        = $db->find_by_id( 'controversy_dump_time_slices', $controversy_dump_time_slices_id );
    my $cd          = $db->find_by_id( 'controversy_dumps',            $cdts->{ controversy_dumps_id } );
    my $controversy = $db->find_by_id( 'controversies',                $cd->{ controversies_id } );

    my $medium = _get_cdts_medium_and_stories( $db, $cdts, $media_id );
    my $live_medium = _get_live_medium_and_stories( $db, $controversy, $media_id );

    my $live_medium_diffs = _get_live_medium_diffs( $medium, $live_medium );

    my $latest_controversy_dump = _get_latest_controversy_dump( $db, $cdts );

    $c->stash->{ cdts }                    = $cdts;
    $c->stash->{ cd }                      = $cd;
    $c->stash->{ controversy }             = $controversy;
    $c->stash->{ medium }                  = $medium;
    $c->stash->{ latest_controversy_dump } = $latest_controversy_dump;
    $c->stash->{ live_medium_diffs }       = $live_medium_diffs;
    $c->stash->{ template }                = 'cm/medium.tt2';
}

1;
