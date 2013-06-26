package MediaWords::Controller::Admin::CM;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;
use warnings;
use parent 'Catalyst::Controller';

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

    $c->stash->{ controversies }    = $controversies;
    $c->stash->{ template }         = 'cm/list.tt2';
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
    
    $c->stash->{ controversy }          = $controversy;
    $c->stash->{ query }                = $query;
    $c->stash->{ controversy_dumps }    = $controversy_dumps;
    $c->stash->{ template }             = 'cm/view.tt2';
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

# view medium as it existed at the time of the dump
sub medium : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id, $media_id ) = @_;
    
    my $db = $c->dbis;

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $controversy_dump_time_slices_id );
    my $cd = $db->find_by_id( 'controversy_dumps', $cdts->{ controversy_dumps_id } );
    my $controversy = $db->find_by_id( 'controversies', $cd->{ controversies_id } );
    
    my $medium = $db->query( <<END, $controversy_dump_time_slices_id, $media_id )->hash;
select m.*, mlc.inlink_count, mlc.outlink_count 
    from cd.media m, cd.medium_link_counts mlc, controversy_dump_time_slices cdts
    where m.media_id = mlc.media_id and
        cdts.controversy_dump_time_slices_id = ? and
        m.media_id = ? and
        mlc.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id and
        m.controversy_dumps_id = cdts.controversy_dumps_id
END

    my $medium_stories = $db->query( <<END, $controversy_dump_time_slices_id, $media_id )->hashes;
select s.*, slc.inlink_count, slc.outlink_count
    from cd.stories s, cd.story_link_counts slc, controversy_dump_time_slices cdts
    where s.stories_id = slc.stories_id and
        cdts.controversy_dump_time_slices_id = ? and
        s.media_id = ? and
        s.controversy_dumps_id = cdts.controversy_dumps_id and
        slc.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id
    order by slc.inlink_count desc
END

    my $inlink_stories = $db->query( <<END, $media_id, $controversy_dump_time_slices_id )->hashes;
select a.*, q.story_count, m.name medium_name
    from cd.stories a, cd.media m,
        ( select cdts.controversy_dumps_id, s.stories_id, count(*) story_count
            from cd.stories s, cd.stories r, 
                cd.controversy_links_cross_media cl, controversy_dump_time_slices cdts
            where s.stories_id = cl.stories_id and
                cl.ref_stories_id = r.stories_id and
                r.media_id = ? and
                cdts.controversy_dump_time_slices_id = ? and
                s.controversy_dumps_id = cdts.controversy_dumps_id and
                r.controversy_dumps_id = cdts.controversy_dumps_id
            group by cdts.controversy_dumps_id, s.stories_id
        ) q
    where q.stories_id = a.stories_id and
        a.controversy_dumps_id = q.controversy_dumps_id and
        a.media_id = m.media_id and
        m.controversy_dumps_id = q.controversy_dumps_id
    order by q.story_count desc
END

    $c->stash->{ cdts }             = $cdts;
    $c->stash->{ cd }               = $cd;
    $c->stash->{ controversy }      = $controversy;
    $c->stash->{ medium }           = $medium;
    $c->stash->{ medium_stories }   = $medium_stories;
    $c->stash->{ inlink_stories }   = $inlink_stories;
    $c->stash->{ template }         = 'cm/medium.tt2';
}

1;
