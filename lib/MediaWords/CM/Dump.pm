package MediaWords::CM::Dump;

# code to analyze a controversy and dump the controversy to snapshot tables and a gexf file

use strict;
use warnings;

use Data::Dumper;
use Date::Format;
use Encode;
use File::Temp;
use FileHandle;
use Getopt::Long;
use XML::Simple;

use MediaWords::CM::Model;
use MediaWords::DBI::Media;
use MediaWords::Util::CSV;
use MediaWords::Util::Colors;
use MediaWords::Util::Config;
use MediaWords::Util::SQL;
use MediaWords::DBI::Activities;

# max and mind node sizes for gexf dump
use constant MAX_NODE_SIZE => 50;
use constant MIN_NODE_SIZE => 5;

# max map width for gexf dump
use constant MAX_MAP_WIDTH => 800;

# consistent colors for media types
my $_media_type_color_map;

# attributes to include in gexf dump
my $_media_static_gexf_attribute_types = {
    url          => 'string',
    inlink_count => 'integer',
    story_count  => 'integer',
    view_medium  => 'string'
};

# all tables that the dump process snapshots for each controversy_dump
my $_snapshot_tables = [
    qw/controversy_stories controversy_links_cross_media controversy_media_codes
      stories media stories_tags_map media_tags_map tags tag_sets/
];

# tablespace clause for temporary tables
my $_temporary_tablespace;

# temporary hack to get around dump_period_stories lock
my $_drop_dump_period_stories = 1;

# get the list of all snapshot tables
sub get_snapshot_tables
{
    return [ @{ $_snapshot_tables } ];
}

# if the temporary_table_tablespace config is present, set $_temporary_tablespace
# to a tablespace clause for the tablespace, otherwise set it to ''
sub set_temporary_table_tablespace
{
    my $config = MediaWords::Util::Config::get_config;

    my $tablespace = $config->{ mediawords }->{ temporary_table_tablespace };

    $_temporary_tablespace = $tablespace ? "tablespace $tablespace" : '';
}

# create all of the temporary dump* tables other than medium_links and story_links
sub write_live_dump_tables
{
    my ( $db, $controversy, $cdts ) = @_;

    my $controversies_id;
    if ( $controversy )
    {
        $controversies_id = $controversy->{ controversies_id };
    }
    else
    {
        my $cd = $db->find_by_id( 'controversy_dumps', $cdts->{ controversy_dumps_id } );
        $controversies_id = $cd->{ controversies_id };
    }

    write_temporary_dump_tables( $db, $controversies_id );
    write_period_stories( $db, $cdts );
    write_story_link_counts_dump( $db, $cdts, 1 );
    write_story_links_dump( $db, $cdts, 1 );
    write_medium_link_counts_dump( $db, $cdts, 1 );
    write_medium_links_dump( $db, $cdts, 1 );
}

# create temporary view of all the dump_* tables that call into the cd.* tables.
# this is useful for writing queries on the cd.* tables without lots of ugly
# joins and clauses to cd and cdts.  It also provides the same set of dump_*
# tables as provided by write_story_link_counts_dump_tables, so that the same
# set of queries can run against either.
sub create_temporary_dump_views
{
    my ( $db, $cdts ) = @_;

    my $snapshot_tables = get_snapshot_tables();

    for my $t ( @{ $snapshot_tables } )
    {
        $db->query( <<END );
create temporary view dump_$t as select * from cd.$t 
    where controversy_dumps_id = $cdts->{ controversy_dumps_id }
END
    }

    for my $t ( qw(story_link_counts story_links medium_link_counts medium_links) )
    {
        $db->query( <<END )
create temporary view dump_$t as select * from cd.$t 
    where controversy_dump_time_slices_id = $cdts->{ controversy_dump_time_slices_id }
END
    }
}

# setup dump_* tables by either creating views for the relevant cd.*
# tables for a dump snapshot or by copying live data for live requests.
sub setup_temporary_dump_tables
{
    my ( $db, $cdts, $controversy, $live ) = @_;

    # postgres prints lots of 'NOTICE's when deleting temp tables
    $db->dbh->{ PrintWarn } = 0;

    if ( $live )
    {
        MediaWords::CM::Dump::write_live_dump_tables( $db, $controversy, $cdts );
    }
    else
    {
        MediaWords::CM::Dump::create_temporary_dump_views( $db, $cdts );
    }
}

# run $db->query( "discard temp" ) to clean up temp tables and views
sub discard_temp_tables
{
    my ( $db ) = @_;

    $db->query( "discard temp" );
}

# remove stories from dump_period_stories that don't match the $csts->{ tags_id }, if present
sub restrict_period_stories_to_tag
{
    my ( $db, $cdts ) = @_;

    return unless ( $cdts->{ tags_id } );

    # it may be a little slower to add all the rows and then delete them, but
    # it makes the code much cleaner
    $db->query( <<END, $cdts->{ tags_id } );
delete from dump_period_stories s where not exists
        ( select 1 from stories_tags_map stm where stm.stories_id = s.stories_id and stm.tags_id = ? )
END

}

# get the where clause that will restrict the dump_period_stories creation
# to only stories within the cdts time frame
sub get_period_stories_date_where_clause
{
    my ( $cdts ) = @_;

    my $date_clause = <<END;
( ( s.publish_date between \$1::timestamp and \$2::timestamp - interval '1 second' 
      and s.stories_id not in ( select stories_id from dump_undateable_stories ) ) or
  ( ss.publish_date between \$1::timestamp and \$2::timestamp - interval '1 second'
      and ss.stories_id not in ( select stories_id from dump_undateable_stories ) )
)
END

    return $date_clause;
}

# write dump_period_stories table that holds list of all stories that should be included in the
# current period.  For an overall dump, every story should be in the current period.
# For other dumps, a story should be in the current dump if either its date is within
# the period dates or if a story that links to it has a date within the period dates.
# For this purpose, stories tagged with the 'date_invalid:undateable' tag
# are considered to have an invalid tag, so their dates cannot be used to pass
# either of the above tests.
#
# The resulting dump_period_stories should be used by all other dump queries to determine
# story membership within a give period.
sub write_period_stories
{
    my ( $db, $cdts ) = @_;

    $db->query( "drop table if exists dump_period_stories" );

    if ( !$cdts || ( !$cdts->{ tags_id } && ( $cdts->{ period } eq 'overall' ) ) )
    {
        $db->query( <<END );
create temporary table dump_period_stories $_temporary_tablespace as select stories_id from dump_stories
END
    }
    else
    {
        $db->query( <<END );
create or replace temporary view dump_undateable_stories as
    select distinct s.stories_id
        from dump_stories s, dump_stories_tags_map stm, dump_tags t, dump_tag_sets ts
        where s.stories_id = stm.stories_id and
            stm.tags_id = t.tags_id and
            t.tag_sets_id = ts.tag_sets_id and
            ts.name = 'date_invalid' and
            t.tag = 'undateable'
END

        my $date_where_clause = get_period_stories_date_where_clause( $cdts );

        $db->query( <<"END", $cdts->{ start_date }, $cdts->{ end_date } );
create temporary table dump_period_stories $_temporary_tablespace as
    select distinct s.stories_id
        from dump_stories s
            left join dump_controversy_links_cross_media cl on ( cl.ref_stories_id = s.stories_id )
            left join dump_stories ss on ( cl.stories_id = ss.stories_id )
        where 
            $date_where_clause
END

        $db->query( "drop view dump_undateable_stories" );
    }

    if ( $cdts->{ tags_id } )
    {
        restrict_period_stories_to_tag( $db, $cdts );
    }
}

sub create_cdts_file
{
    my ( $db, $cdts, $file_name, $file_content ) = @_;

    my $cdts_file = {
        controversy_dump_time_slices_id => $cdts->{ controversy_dump_time_slices_id },
        file_name                       => $file_name,
        file_content                    => $file_content
    };

    return $db->create( 'cdts_files', $cdts_file );
}

sub create_cd_file
{
    my ( $db, $cd, $file_name, $file_content ) = @_;

    my $cd_file = {
        controversy_dumps_id => $cd->{ controversy_dumps_id },
        file_name            => $file_name,
        file_content         => $file_content
    };

    return $db->create( 'cd_files', $cd_file );
}

# convenience function to update a field in the cdts table
sub update_cdts
{
    my ( $db, $cdts, $field, $val ) = @_;

    $db->update_by_id( 'controversy_dump_time_slices', $cdts->{ controversy_dump_time_slices_id }, { $field => $val } );
}

sub get_story_links_csv
{
    my ( $db, $cdts ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<END );
select distinct sl.source_stories_id source_stories_id, ss.title source_title, ss.url source_url, 
        sm.name source_media_name, sm.url source_media_url, sm.media_id source_media_id,
		sl.ref_stories_id ref_stories_id, rs.title ref_title, rs.url ref_url, rm.name ref_media_name, rm.url ref_media_url, 
		rm.media_id ref_media_id
	from dump_story_links sl, cd.live_stories ss, media sm, cd.live_stories rs, media rm
	where sl.source_stories_id = ss.stories_id and 
	    ss.media_id = sm.media_id and 
	    sl.ref_stories_id = rs.stories_id and 
	    rs.media_id = rm.media_id
END

    return $csv;
}

sub write_story_links_csv
{
    my ( $db, $cdts ) = @_;

    my $csv = get_story_links_csv( $db, $cdts );

    create_cdts_file( $db, $cdts, 'story_links.csv', $csv );
}

sub write_story_links_dump
{
    my ( $db, $cdts, $is_model ) = @_;

    $db->query( "drop table if exists dump_story_links" );

    $db->query( <<END );
create temporary table dump_story_links $_temporary_tablespace as
    select distinct cl.stories_id source_stories_id, cl.ref_stories_id
	    from dump_controversy_links_cross_media cl, dump_period_stories sps, dump_period_stories rps
    	where cl.stories_id = sps.stories_id and
    	    cl.ref_stories_id = rps.stories_id
END

    # re-enable above to prevent post-dated links
    #          ss.publish_date > rs.publish_date - interval '1 day' and

    if ( !$is_model )
    {
        create_cdts_snapshot( $db, $cdts, 'story_links' );
        write_story_links_csv( $db, $cdts );
    }
}

sub get_stories_csv
{
    my ( $db, $cdts ) = @_;

    my $controversy = $db->query( <<END, $cdts->{ controversy_dumps_id } );
select * from controversies c, controversy_dumps cd
    where c.controversies_id = cd.controversies_id and cd.controversy_dumps_id = ?
END

    my $tagset_name = "Controversy $cdts->{ controversy_dump }->{ controversy }->{ name }";

    my $tags = $db->query( <<END, $tagset_name )->hashes;
select * from dump_tags t, dump_tag_sets ts 
    where t.tag_sets_id = ts.tag_sets_id and ts.name = ? and t.tag <> 'all'
END

    my $tag_clauses = [];
    for my $tag ( @{ $tags } )
    {
        my $label = "tagged_" . $tag->{ tag };

        push(
            @{ $tag_clauses },
            "exists ( select 1 from dump_stories_tags_map stm " .
              "  where s.stories_id = stm.stories_id and stm.tags_id = $tag->{ tags_id } ) $label "
        );
    }

    my $tag_clause_list = join( ',', @{ $tag_clauses } );
    $tag_clause_list = ", $tag_clause_list" if ( $tag_clause_list );

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<END );
select distinct s.stories_id, s.title, s.url,
        case when ( stm.tags_id is null ) then s.publish_date::text else 'undateable' end as publish_date,
        m.name media_name, m.url media_url, m.media_id,
        slc.inlink_count, slc.outlink_count $tag_clause_list
	from dump_stories s
	    join dump_media m on ( s.media_id = m.media_id )
	    join dump_story_link_counts slc on ( s.stories_id = slc.stories_id ) 
	    left join (
	        stories_tags_map stm
                join tags t on ( stm.tags_id = t.tags_id  and t.tag = 'undateable' )
                join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id and ts.name = 'date_invalid' ) )
            on ( stm.stories_id = s.stories_id )
	order by slc.inlink_count
END

    return $csv;
}

sub write_stories_csv
{
    my ( $db, $cdts ) = @_;

    my $csv = get_stories_csv( $db, $cdts );

    create_cdts_file( $db, $cdts, 'stories.csv', $csv );
}

sub write_story_link_counts_dump
{
    my ( $db, $cdts, $is_model ) = @_;

    $db->query( "drop table if exists dump_story_link_counts" );

    $db->query( <<END );
create temporary table dump_story_link_counts $_temporary_tablespace as
    select distinct ps.stories_id, 
            coalesce( ilc.inlink_count, 0 ) inlink_count, 
            coalesce( olc.outlink_count, 0 ) outlink_count
        from dump_period_stories ps
            left join 
                ( select cl.ref_stories_id, count( distinct cl.stories_id ) inlink_count 
                    from dump_controversy_links_cross_media cl, dump_period_stories ps
                    where cl.stories_id = ps.stories_id
                    group by cl.ref_stories_id ) ilc on ( ps.stories_id = ilc.ref_stories_id )
            left join 
                ( select cl.stories_id, count( distinct cl.ref_stories_id ) outlink_count 
                    from dump_controversy_links_cross_media cl, dump_period_stories ps
                    where cl.ref_stories_id = ps.stories_id
                    group by cl.stories_id ) olc on ( ps.stories_id = olc.stories_id )
END

    if ( !$is_model )
    {
        create_cdts_snapshot( $db, $cdts, 'story_link_counts' );
        write_stories_csv( $db, $cdts );
    }
}

sub add_tags_to_dump_media
{
    my ( $db, $cdts, $media ) = @_;

    my $tagset_name = "controversy_$cdts->{ controversy_dump }->{ controversy }->{ name }";

    my $tags = $db->query( <<END, $tagset_name )->hashes;
select * from dump_tags t, dump_tag_sets ts
  where t.tag_sets_id = ts.tag_sets_id and ts.name = ? and t.tag <> 'all'
END

    my $tag_fields = [];
    for my $tag ( @{ $tags } )
    {
        my $label = "tagged_" . $tag->{ tag };

        push( @{ $tag_fields }, $label );

        my $media_tags = $db->query( <<END, $tag->{ tags_id } )->hashes;
select s.media_id, stm.* 
    from dump_stories s, dump_story_link_counts slc, dump_stories_tags_map stm 
    where s.stories_id = slc.stories_id and s.stories_id = stm.stories_id and stm.tags_id = ?
END
        my $media_tags_map = {};
        map { $media_tags_map->{ $_->{ media_id } } += 1 } @{ $media_tags };

        map { $_->{ $label } = $media_tags_map->{ $_->{ media_id } } || 0 } @{ $media };
    }

    return $tag_fields;
}

sub add_codes_to_dump_media
{
    my ( $db, $cdts, $media ) = @_;

    my $code_types = $db->query( <<END )->flat;
select distinct code_type from dump_controversy_media_codes
END

    my $code_fields = [];
    for my $code_type ( @{ $code_types } )
    {
        my $label = "code_" . $code_type;

        push( @{ $code_fields }, $label );

        my $media_codes = $db->query( <<END, $code_type )->hashes;
select * from dump_controversy_media_codes where code_type = ?
END
        my $media_codes_map = {};
        map { $media_codes_map->{ $_->{ media_id } } = $_->{ code } } @{ $media_codes };

        map { $_->{ $label } = $media_codes_map->{ $_->{ media_id } } || 'null' } @{ $media };
    }

    return $code_fields;
}

sub get_media_csv
{
    my ( $db, $cdts ) = @_;

    my $res = $db->query( <<END );
select m.media_id, m.name, m.url, mlc.inlink_count, mlc.outlink_count, mlc.story_count
    from dump_media m, dump_medium_link_counts mlc
    where m.media_id = mlc.media_id
    order by mlc.inlink_count desc;
END

    my $fields = $res->columns;
    my $media  = $res->hashes;

    my $code_fields = add_codes_to_dump_media( $db, $cdts, $media );
    my $tag_fields = add_tags_to_dump_media( $db, $cdts, $media );

    push( @{ $fields }, @{ $code_fields } );
    push( @{ $fields }, @{ $tag_fields } );

    my $csv = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $media, $fields );

    return $csv;
}

sub write_media_csv
{
    my ( $db, $cdts ) = @_;

    my $csv = get_media_csv( $db, $cdts );

    create_cdts_file( $db, $cdts, 'media.csv', $csv );
}

sub write_medium_link_counts_dump
{
    my ( $db, $cdts, $is_model ) = @_;

    $db->query( "drop table if exists dump_medium_link_counts" );

    $db->query( <<END );
create temporary table dump_medium_link_counts $_temporary_tablespace as   
    select m.media_id, sum( slc.inlink_count) inlink_count, sum( slc.outlink_count) outlink_count,
            count(*) story_count
        from dump_media m, dump_stories s, dump_story_link_counts slc 
        where m.media_id = s.media_id and s.stories_id = slc.stories_id
        group by m.media_id
END

    if ( !$is_model )
    {
        create_cdts_snapshot( $db, $cdts, 'medium_link_counts' );
        write_media_csv( $db, $cdts );
    }
}

sub get_medium_links_csv
{
    my ( $db, $cdts ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<END );
select ml.source_media_id, sm.name source_name, sm.url source_url,
        ml.ref_media_id, rm.name ref_name, rm.url ref_url, ml.link_count 
    from dump_medium_links ml, media sm, media rm
    where ml.source_media_id = sm.media_id and ml.ref_media_id = rm.media_id
END

    return $csv;
}

sub write_medium_links_csv
{
    my ( $db, $cdts ) = @_;

    my $csv = get_medium_links_csv( $db, $cdts );

    create_cdts_file( $db, $cdts, 'medium_links.csv', $csv );
}

sub write_medium_links_dump
{
    my ( $db, $cdts, $is_model ) = @_;

    $db->query( "drop table if exists dump_medium_links" );

    $db->query( <<END );
create temporary table dump_medium_links $_temporary_tablespace as
    select s.media_id source_media_id, r.media_id ref_media_id, count(*) link_count
        from dump_story_links sl, dump_stories s, dump_stories r
        where sl.source_stories_id = s.stories_id and sl.ref_stories_id = r.stories_id
        group by s.media_id, r.media_id
END

    if ( !$is_model )
    {
        create_cdts_snapshot( $db, $cdts, 'medium_links' );
        write_medium_links_csv( $db, $cdts );
    }
}

sub write_date_counts_csv
{
    my ( $db, $cd, $period ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<END );
select dc.publish_date, t.tag, t.tags_id, dc.story_count
    from dump_${ period }_date_counts dc, tags t
    where dc.tags_id = t.tags_id
    order by t.tag, dc.publish_date
END

    create_cd_file( $db, $cd, "${ period }_counts.csv", $csv );
}

sub write_date_counts_dump
{
    my ( $db, $cd, $period ) = @_;

    die( "unknown period '$period'" ) unless ( grep { $period eq $_ } qw(daily weekly) );
    my $date_trunc = ( $period eq 'daily' ) ? 'day' : 'week';

    $db->query( <<END, $date_trunc, $date_trunc );
create temporary table dump_${ period }_date_counts $_temporary_tablespace as
    select date_trunc( ?, s.publish_date ) publish_date, t.tags_id, count(*) story_count
        from dump_stories s, dump_stories_tags_map stm, dump_tags t
        where s.stories_id = stm.stories_id and
            stm.tags_id = t.tags_id
        group by date_trunc( ?, s.publish_date ), t.tags_id
END

    create_cd_snapshot( $db, $cd, "${ period }_date_counts" );

    write_date_counts_csv( $db, $cd, $period );
}

sub attach_stories_to_media
{
    my ( $stories, $media ) = @_;

    my $media_lookup = {};
    map { $media_lookup->{ $_->{ media_id } } = $_ } @{ $media };
    map { push( @{ $media_lookup->{ $_->{ media_id } }->{ stories } }, $_ ) } @{ $stories };
}

sub add_tags_to_gexf_attribute_types
{
    my ( $db, $cdts ) = @_;

    my $tagset_name = "controversy_$cdts->{ controversy_dump }->{ controversy }->{ name }";

    my $tags = $db->query( <<END, $tagset_name )->hashes;
select * from dump_tags t, dump_tag_sets ts where t.tag_sets_id = ts.tag_sets_id and ts.name = ? and t.tag <> 'all'
END

    map { $_media_static_gexf_attribute_types->{ "tagged_" . $_->{ tag } } = 'integer' } @{ $tags };
}

sub add_codes_to_gexf_attribute_types
{
    my ( $db, $cdts ) = @_;

    my $code_types = $db->query( "select distinct code_type from dump_controversy_media_codes" )->flat;

    map { $_media_static_gexf_attribute_types->{ "code_" . $_ } = 'string' } @{ $code_types };
}

sub get_link_weighted_edges
{
    my ( $db ) = @_;

    my $media_links = $db->query( "select * from dump_medium_links" )->hashes;

    my $edges = [];
    my $k     = 0;
    for my $media_link ( @{ $media_links } )
    {
        my $edge = {
            id     => $k++,
            source => $media_link->{ source_media_id },
            target => $media_link->{ ref_media_id },
            weight => $media_link->{ inlink_count }
        };

        push( @{ $edges }, $edge );
    }

    return $edges;
}

sub get_weighted_edges
{
    my ( $db ) = @_;

    return get_link_weighted_edges( $db );
}

# given an rgb hex string, return a hash in the form { r => 12, g => 0, b => 255 }, which is
# what we need for the viz:color element of the gexf dump
sub get_color_hash_from_hex
{
    my ( $rgb_hex ) = @_;

    return {
        r => hex( substr( $rgb_hex, 0, 2 ) ),
        g => hex( substr( $rgb_hex, 2, 2 ) ),
        b => hex( substr( $rgb_hex, 4, 2 ) )
    };
}

sub get_media_type_color
{
    my ( $db, $cdts, $media_type ) = @_;

    $media_type ||= 'none';

    return $_media_type_color_map->{ $media_type } if ( $_media_type_color_map );

    my $all_media_types = $db->query( <<END )->flat;
select distinct code from dump_controversy_media_codes where code_type = 'media_type'
END

    my $num_colors = scalar( @{ $all_media_types } ) + 1;

    my $hex_colors = MediaWords::Util::Colors::get_colors( $num_colors );
    my $color_list = [ map { get_color_hash_from_hex( $_ ) } @{ $hex_colors } ];

    $_media_type_color_map = {};
    for my $media_type ( @{ $all_media_types } )
    {
        $_media_type_color_map->{ $media_type } = pop( @{ $color_list } );
    }

    $_media_type_color_map->{ none } = pop( @{ $color_list } );

    return $_media_type_color_map->{ $media_type };
}

# gephi removes the weights from the media links.  add them back in.
sub add_weights_to_gexf_edges
{
    my ( $db, $gexf ) = @_;

    my $edges = $gexf->{ graph }->[ 0 ]->{ edges }->[ 0 ]->{ edge };

    my $medium_links = $db->query( "select * from dump_medium_links" )->hashes;

    my $edge_weight_lookup = {};
    for my $m ( @{ $medium_links } )
    {
        $edge_weight_lookup->{ $m->{ source_media_id } }->{ $m->{ ref_media_id } } = $m->{ link_count };
    }

    for my $edge ( @{ $edges } )
    {
        $edge->{ weight } = $edge_weight_lookup->{ $edge->{ source } }->{ $edge->{ target } };
    }
}

# scale the size of the map described in the gexf file to 800 x 700.
# gephi can return really large maps that make the absolute node size relatively tiny.
# we need to scale the map to get consistent, reasonable node sizes across all maps
sub scale_gexf_nodes
{
    my ( $db, $gexf ) = @_;

    # print Dumper( $gexf );

    my $nodes = $gexf->{ graph }->[ 0 ]->{ nodes }->[ 0 ]->{ node };

    # we assume that the gephi maps are symmetrical and so only check the
    my $max_x;
    for my $node ( @{ $nodes } )
    {
        my $p = $node->{ 'viz:position' }->[ 0 ];
        $max_x = $p->{ x } if ( $p->{ x } > $max_x );
    }

    my $map_width = $max_x * 2;

    if ( $map_width > MAX_MAP_WIDTH )
    {
        my $scale = MAX_MAP_WIDTH / $map_width;

        for my $node ( @{ $nodes } )
        {
            my $p = $node->{ 'viz:position' }->[ 0 ];
            $p->{ x } *= $scale;
            $p->{ y } *= $scale;
        }
    }
}

# post process gexf file.  gephi mucks up the gexf file by making it too big and
# removing the weights from the gexf export.  I can't figure out how to get the gephi toolkit
# to fix these things, so I just fix them in perl
sub post_process_gexf
{
    my ( $db, $gexf_file ) = @_;

    my $gexf = XML::Simple::XMLin( $gexf_file, ForceArray => 1, ForceContent => 1, KeyAttr => [] );

    add_weights_to_gexf_edges( $db, $gexf );

    scale_gexf_nodes( $db, $gexf );

    open( FILE, ">$gexf_file" ) || die( "Unable to open file '$gexf_file': $!" );

    print FILE encode( 'utf8', XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' ) );

    close FILE;

}

# call java program to lay out graph.  the java program accepts a gexf file as input and
# outputs a gexf file with the lay out included
sub layout_gexf
{
    my ( $db, $cdts, $nolayout_gexf ) = @_;

    print STDERR "generating gephi layout ...\n";

    my $tmp_dir = File::Temp::tempdir( "dump_layout_$cdts->{ controversy_dump_time_slices_id }_XXXX" );

    my $nolayout_path = "$tmp_dir/nolayout.gexf";
    my $layout_path   = "$tmp_dir/layout.gexf";

    my $fh = FileHandle->new( ">$nolayout_path" ) || die( "Unable to open file '$nolayout_path': $!" );
    $fh->print( encode( 'utf8', $nolayout_gexf ) );
    $fh->close();

    my $cmd =
"java -cp $FindBin::Bin/../java/GephiLayout/build/jar/GephiLayout.jar:$FindBin::Bin/../java/GephiLayout/lib/gephi-toolkit.jar edu.law.harvard.cyber.mediacloud.layout.GephiLayout $nolayout_path $layout_path";

    # print STDERR "$cmd\n";
    system( $cmd );

    post_process_gexf( $db, $layout_path );

    $fh = FileHandle->new( $layout_path ) || die( "Unable to open file '$layout_path': $!" );

    my $layout_gexf;
    while ( my $line = $fh->getline )
    {
        $layout_gexf .= decode( 'utf8', $line );
    }

    $fh->close;

    unlink( $layout_path, $nolayout_path );
    rmdir( $tmp_dir );

    return $layout_gexf;
}

# get the size of the individual node based on the medium and the total number of links in the graph
sub get_node_size
{
    my ( $medium, $total_link_count ) = @_;

    print STDERR "get_node_size: $medium->{ name } [ $medium->{ inlink_count } / $total_link_count ]\n";

    my $scale = 100;

    # my $min_size = $scale * ( 1 / $total_link_count );
    # $scale = 3 * ( $scale / $min_size ) if ( $min_size < 3 );

    my $size = $scale * ( ( $medium->{ inlink_count } + 1 ) / $total_link_count );

    $size = 1 if ( $size < 1 );

    #print STDERR "size: $size\n";

    return $size;
}

# scale the nodes such that the biggest node size is MAX_NODE_SIZE and the smallest is MIN_NODE_SIZE
sub scale_node_sizes
{
    my ( $nodes ) = @_;

    map { $_->{ 'viz:size' }->{ value } += 1 } @{ $nodes };

    my $max_size = 1;
    map { my $s = $_->{ 'viz:size' }->{ value }; $max_size = $s if ( $max_size < $s ); } @{ $nodes };

    my $scale = MAX_NODE_SIZE / $max_size;
    if ( $scale > 1 )
    {
        $scale = 0.5 + ( $scale / 2 );
    }

    # my $scale = ( $max_size > ( MAX_NODE_SIZE / MIN_NODE_SIZE ) ) ? ( MAX_NODE_SIZE / $max_size ) : 1;

    for my $node ( @{ $nodes } )
    {
        my $s = $node->{ 'viz:size' }->{ value };

        $s = int( $scale * $s );

        $s = MIN_NODE_SIZE if ( $s < MIN_NODE_SIZE );

        $node->{ 'viz:size' }->{ value } = $s;

        # say STDERR "viz:size $s";
    }
}

# write gexf dump of nodes
sub write_gexf_dump
{
    my ( $db, $cdts ) = @_;

    add_tags_to_gexf_attribute_types( $db, $cdts );
    add_codes_to_gexf_attribute_types( $db, $cdts );

    my $media = $db->query( <<END )->hashes;
select * from dump_media m, dump_medium_link_counts mlc where m.media_id = mlc.media_id
END

    add_codes_to_dump_media( $db, $cdts, $media );
    add_tags_to_dump_media( $db, $cdts, $media );

    my $gexf = {
        'xmlns'              => "http://www.gexf.net/1.2draft",
        'xmlns:xsi'          => "http://www.w3.org/2001/XMLSchema-instance",
        'xmlns:viz'          => "http://www.gexf.net/1.1draft/viz",
        'xsi:schemaLocation' => "http://www.gexf.net/1.2draft http://www.gexf.net/1.2draft/gexf.xsd",
        'version'            => "1.2"
    };

    my $meta = { 'lastmodifieddate' => Date::Format::time2str( '%Y-%m-%d', time ) };
    push( @{ $gexf->{ meta } }, $meta );

    push( @{ $meta->{ creator } }, 'Berkman Center' );

    my $controversy = $cdts->{ controversy_dump }->{ controversy };
    push( @{ $meta->{ description } }, "Media discussions of $controversy->{ name }" );

    my $graph = {
        'mode'            => "dynamic",
        'defaultedgetype' => "directed",
        'timeformat'      => "date"
    };
    push( @{ $gexf->{ graph } }, $graph );

    my $attributes = { class => 'node', mode => 'static' };
    push( @{ $graph->{ attributes } }, $attributes );

    my $i = 0;
    while ( my ( $name, $type ) = each( %{ $_media_static_gexf_attribute_types } ) )
    {
        push( @{ $attributes->{ attribute } }, { id => $i++, title => $name, type => $type } );
    }

    my $edges = get_weighted_edges( $db );
    $graph->{ edges }->{ edge } = $edges;

    my $edge_lookup = {};
    for my $edge ( @{ $edges } )
    {
        $edge_lookup->{ $edge->{ source } } ||= 0;
        $edge_lookup->{ $edge->{ target } } += $edge->{ weight };
    }

    my $total_link_count = 1;
    map { $total_link_count += $_->{ inlink_count } } @{ $media };

    for my $medium ( @{ $media } )
    {
        next unless ( $medium->{ inlink_count } || $medium->{ outlink_count } );

        my $node = {
            id    => $medium->{ media_id },
            label => $medium->{ name },
        };

        $medium->{ view_medium } =
          "[_mc_base_url_]/admin/cm/medium/$medium->{ media_id }?cdts=$cdts->{ controversy_dump_time_slices_id }";

        my $j = 0;
        while ( my ( $name, $type ) = each( %{ $_media_static_gexf_attribute_types } ) )
        {
            push( @{ $node->{ attvalues }->{ attvalue } }, { for => $j++, value => $medium->{ $name } } );
        }

        # for my $story ( @{ $medium->{ stories } } )
        # {
        #     my $story_date = substr( $story->{ publish_date }, 0, 10 );
        #     push( @{ $node->{ spells }->{ spell } }, { start => $story_date, end => $story_date } );
        # }

        $node->{ 'viz:color' } = [ get_media_type_color( $db, $cdts, $medium->{ code_media_type } ) ];
        $node->{ 'viz:size' } = { value => $medium->{ inlink_count } + 1 };

        push( @{ $graph->{ nodes }->{ node } }, $node );
    }

    scale_node_sizes( $graph->{ nodes }->{ node } );

    my $nolayout_gexf = XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' );

    my $layout_gexf = layout_gexf( $db, $cdts, $nolayout_gexf );

    create_cdts_file( $db, $cdts, 'media.gexf', encode( 'utf8', $layout_gexf ) );
}

# return true if there are any stories in the current controversy_stories_dump_ table
sub stories_exist_for_period
{
    my ( $db, $controversy ) = @_;

    return $db->query( "select 1 from dump_period_stories" )->hash;
}

# dump csv of all links from one story to another in the given story's future
sub write_post_dated_links_dump
{
    my ( $db, $controversy ) = @_;

    write_dump_as_csv( $db, $controversy, 'controversy_post_dated_links_dump', <<END );
select count(*) post_dated_links, sb.stories_id, min( sb.url ) url, min( sb.publish_date ) publish_date 
    from stories sa, stories sb, controversy_links_cross_media cl 
    where sa.stories_id = cl.stories_id and sb.stories_id = cl.ref_stories_id and 
        sa.publish_date < sb.publish_date - interval '1 day' and 
        not ( sa.url like '%google.search%' ) and
        cl.controversies_id = $controversy->{ controversies_id }
    group by sb.stories_id order by count(*) desc;
END

}

# dump csv of all stories linking to another in the given story's future
sub write_post_dated_stories_dump
{
    my ( $db, $controversy ) = @_;

    write_dump_as_csv( $db, $controversy, 'controversy_post_dated_stories_dump', <<END );
select distinct sa.stories_id, sa.url, sa.publish_date, 
        count(sa.stories_id) OVER (PARTITION BY sb.stories_id) post_dated_stories, sb.stories_id ref_stories_id, 
        sb.url ref_url, sb.publish_date ref_publish_date 
    from stories sa, stories sb, controversy_links_cross_media cl 
    where sa.stories_id = cl.stories_id and sb.stories_id = cl.ref_stories_id and 
        sa.publish_date < sb.publish_date - interval '1 day' and 
        not ( sa.url like '%sopa.google.search%' ) and
        cl.controversies_id = $controversy->{ controversies_id }
    order by post_dated_stories desc, sb.stories_id, sa.publish_date;
END

}

# dump counts of distinct url domains for the last 1000 stories for each media source in the controversy
sub write_media_domains_dump
{
    my ( $db, $controversy ) = @_;

    my $res = $db->query( <<END );
select m.* from media m
    where m.media_id in 
        ( select s.media_id from stories s, controversy_stories cs
              where s.stories_id = cs.stories_id and 
                  cs.controversies_id = $controversy->{ controversies_id } )
    order by m.media_id
END

    my $media_fields = $res->columns;
    my $media        = $res->hashes;

    print STDERR "generating media domains ...\n";

    my $num_media = scalar( @{ $media } );
    my $i         = 0;
    for my $medium ( @{ $media } )
    {
        print STDERR "[ $i / $num_media ]\n" unless ( ++$i % 100 );

        my $domain_map = MediaWords::DBI::Media::get_medium_domain_counts( $db, $medium );

        $medium->{ num_domains } = scalar( values( %{ $domain_map } ) );

        my $domain_counts = [];
        while ( my ( $domain, $count ) = each( %{ $domain_map } ) )
        {
            push( @{ $domain_counts }, "[ $domain $count ]" );
        }

        $medium->{ domain_counts } = join( " ", @{ $domain_counts } );

    }

    my $fields = [ shift( @{ $media_fields } ), ( 'num_domains', 'domain_counts' ), @{ $media_fields } ];
    my $csv_string = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $media, $fields );

    write_dump_file( $controversy, 'controversy_media_domains', 'csv', $csv_string );
}

# generate list of all stories with duplicate titles, sorted by title
sub write_dup_stories_dump
{
    my ( $db, $controversy ) = @_;

    write_dump_as_csv( $db, $controversy, 'controversy_dup_stories_dump', <<END );
select sa.title, sa.stories_id stories_id_a, sa.publish_date publish_date_a, sa.url story_url_a,
        sa.media_id media_id_a, ma.url media_url_a, ma.name media_name_a,
        sb.stories_id stories_id_b, sb.publish_date publish_date_b, sb.url story_url_b,
        sb.media_id media_id_b, mb.url media_url_b, mb.name media_name_b
    from controversy_stories csa, stories sa, media ma,
        controversy_stories csb, stories sb, media mb
    where csa.controversies_id = $controversy->{ controversies_id } and 
        csa.stories_id = sa.stories_id and sa.media_id = ma.media_id and
        csb.controversies_id = csa.controversies_id and 
        csb.stories_id = sb.stories_id and sb.media_id = mb.media_id and
        sa.stories_id > sb.stories_id and sa.title = sb.title and
        length( sa.title ) > 16
    order by sa.title, sa.stories_id, sb.stories_id        
END
}

sub create_controversy_dump_time_slice ($$$$$$)
{
    my ( $db, $cd, $start_date, $end_date, $period, $tag ) = @_;

    my $cdts = {
        controversy_dumps_id => $cd->{ controversy_dumps_id },
        start_date           => $start_date,
        end_date             => $end_date,
        period               => $period,
        story_count          => 0,
        story_link_count     => 0,
        medium_count         => 0,
        medium_link_count    => 0,
        tags_id              => $tag ? $tag->{ tags_id } : undef
    };

    $cdts = $db->create( 'controversy_dump_time_slices', $cdts );

    $cdts->{ controversy_dump } = $cd;

    return $cdts;
}

# write cd.word_counts table for time slice
sub write_word_counts
{
    my ( $db, $cdts ) = @_;

    $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } );
insert into cd.word_counts 
    ( controversy_dump_time_slices_id, stem, term, stem_count )
    select ?, ssw.stem, min( term ) term, sum( ssw.stem_count ) stem_count
        from story_sentence_words ssw
            join dump_period_stories ps on ( ssw.stories_id = ps.stories_id )
        group by ssw.stem
END
}

# generate data for the story_links, story_link_counts, media_links, media_link_counts tables
# based on the data in the temporary dump_* tables
sub generate_cdts_data ($$;$)
{
    my ( $db, $cdts, $is_model ) = @_;

    write_period_stories( $db, $cdts );

    write_story_link_counts_dump( $db, $cdts, $is_model );
    write_story_links_dump( $db, $cdts, $is_model );
    write_medium_link_counts_dump( $db, $cdts, $is_model );
    write_medium_links_dump( $db, $cdts, $is_model );

    #write_word_counts( $db, $cdts ) unless ( $is_model );
}

# update *_count fields in cdts.  save to db unless $live is specified.
sub update_cdts_counts ($$;$)
{
    my ( $db, $cdts, $live ) = @_;

    ( $cdts->{ story_count } ) = $db->query( "select count(*) from dump_story_link_counts" )->flat;

    ( $cdts->{ story_link_count } ) = $db->query( "select count(*) from dump_story_links" )->flat;

    ( $cdts->{ medium_count } ) = $db->query( "select count(*) from dump_medium_link_counts" )->flat;

    ( $cdts->{ medium_link_count } ) = $db->query( "select count(*) from dump_medium_links" )->flat;

    return if ( $live );

    for my $field ( qw(story_count story_link_count medium_count medium_link_count) )
    {
        update_cdts( $db, $cdts, $field, $cdts->{ $field } );
    }
}

# generate the dump time slices for the given period, dates, and tag
sub generate_cdts ($$$$$$)
{
    my ( $db, $cd, $start_date, $end_date, $period, $tag ) = @_;

    my $cdts = create_controversy_dump_time_slice( $db, $cd, $start_date, $end_date, $period, $tag );

    my $dump_label = "${ period }: ${ start_date } - ${ end_date } " . ( $tag ? "[ $tag->{ tag } ]" : "" );
    print "generating $dump_label ...\n";

    my $all_models_top_media = MediaWords::CM::Model::get_all_models_top_media( $db, $cdts );

    print "\ngenerating dump data ...\n";
    generate_cdts_data( $db, $cdts );

    update_cdts_counts( $db, $cdts );

    if ( $all_models_top_media )
    {
        MediaWords::CM::Model::print_model_matches( $db, $cdts, $all_models_top_media );
        MediaWords::CM::Model::update_model_correlation( $db, $cdts, $all_models_top_media );
    }

    # my $confidence = get_model_confidence( $db, $cdts, $all_models_top_media );
    # print "confidence: $confidence\n";

    write_gexf_dump( $db, $cdts );
}

# decrease the given date to the latest monday equal to or before the date
sub truncate_to_monday ($)
{
    my ( $date ) = @_;

    my $epoch_date = MediaWords::Util::SQL::get_epoch_from_sql_date( $date );
    my $week_day   = ( localtime( $epoch_date ) )[ 6 ];

    # mod this to account for sunday, for which $week_day - 1 == -1
    my $days_offset = ( $week_day - 1 ) % 7;

    return MediaWords::Util::SQL::increment_day( $date, -1 * $days_offset );
}

# decrease the given date to the first day of the current month
sub truncate_to_start_of_month ($)
{
    my ( $date ) = @_;

    my $epoch_date = MediaWords::Util::SQL::get_epoch_from_sql_date( $date );
    my $month_day  = ( localtime( $epoch_date ) )[ 3 ];

    my $days_offset = $month_day - 1;

    return MediaWords::Util::SQL::increment_day( $date, -1 * $days_offset );
}

# generate dumps for the periods in controversy_dates
sub generate_custom_period_dump ($$$ )
{
    my ( $db, $cd, $tag ) = @_;

    my $controversy_dates = $db->query( <<END, $cd->{ controversies_id } )->hashes;
select * from controversy_dates where controversies_id = ? order by start_date, end_date
END

    for my $controversy_date ( @{ $controversy_dates } )
    {
        my $start_date = $controversy_date->{ start_date };
        my $end_date   = $controversy_date->{ end_date };
        generate_cdts( $db, $cd, $start_date, $end_date, 'custom', $tag );
    }
}

# generate dump for the given period (overall, monthly, weekly, or custom) and the given tag
sub generate_period_dump ($$$$)
{
    my ( $db, $cd, $period, $tag ) = @_;

    my $start_date = $cd->{ start_date };
    my $end_date   = $cd->{ end_date };

    if ( $period eq 'overall' )
    {
        generate_cdts( $db, $cd, $start_date, $end_date, $period, $tag );
    }
    elsif ( $period eq 'weekly' )
    {
        my $w_start_date = truncate_to_monday( $start_date );
        while ( $w_start_date lt $end_date )
        {
            my $w_end_date = MediaWords::Util::SQL::increment_day( $w_start_date, 7 );

            generate_cdts( $db, $cd, $w_start_date, $w_end_date, $period, $tag );

            $w_start_date = $w_end_date;
        }
    }
    elsif ( $period eq 'monthly' )
    {
        my $m_start_date = truncate_to_start_of_month( $start_date );
        while ( $m_start_date lt $end_date )
        {
            my $m_end_date = MediaWords::Util::SQL::increment_day( $m_start_date, 32 );
            $m_end_date = truncate_to_start_of_month( $m_end_date );

            generate_cdts( $db, $cd, $m_start_date, $m_end_date, $period, $tag );

            $m_start_date = $m_end_date;
        }
    }
    elsif ( $period eq 'custom' )
    {
        generate_custom_period_dump( $db, $cd, $tag );
    }
    else
    {
        die( "Unknown period '$period'" );
    }
}

# get default start and end dates from the query associated with the query_stories_search associated with the controversy
sub get_default_dates
{
    my ( $db, $controversy ) = @_;

    my ( $start_date, $end_date ) = $db->query( <<END, $controversy->{ controversies_id } )->flat;
select min( cd.start_date ), max( cd.end_date ) from controversy_dates cd where cd.controversies_id = ?
END

    die( "Unable to find default dates" ) unless ( $start_date && $end_date );

    return ( $start_date, $end_date );

}

# write various dumps useful for cleaning up the dataset.  some of these take quite
# a while to run, so we only want to generate them if needed
sub write_cleanup_dumps
{
    my ( $db, $controversy ) = @_;

    set_dump_label( 'cleanup' );

    write_post_dated_links_dump( $db, $controversy );
    write_post_dated_stories_dump( $db, $controversy );
    write_media_domains_dump( $db, $controversy );
    write_dup_stories_dump( $db, $controversy );
}

# create temporary table copies of temporary tables so that we can copy
# the data back into the main temporary tables after tweaking the main temporary tables
sub copy_temporary_tables
{
    my ( $db ) = @_;

    my $snapshot_tables = get_snapshot_tables();
    for my $snapshot_table ( @{ $snapshot_tables } )
    {
        my $dump_table = "dump_${ snapshot_table }";
        my $copy_table = "_copy_${ dump_table }";

        $db->query( "drop table if exists $copy_table" );
        $db->query( "create temporary table $copy_table $_temporary_tablespace as select * from $dump_table" );
    }
}

# restore original, copied data back into dump tables
sub restore_temporary_tables
{
    my ( $db ) = @_;

    my $snapshot_tables = MediaWords::CM::Dump::get_snapshot_tables();
    for my $snapshot_table ( @{ $snapshot_tables } )
    {
        my $dump_table = "dump_${ snapshot_table }";
        my $copy_table = "_copy_${ dump_table }";

        $db->query( "drop table if exists $dump_table cascade" );
        $db->query( "create temporary table $dump_table $_temporary_tablespace as select * from $copy_table" );
    }
}

# create a snapshot for the given table from the temporary dump_* table,
# making sure to specify all the fields in the copy so that we don't have to
# assume column position is the same in the original and snapshot tables.
# use the $key from $obj as an additional field in the snapshot table.
sub create_snapshot
{
    my ( $db, $obj, $key, $table ) = @_;

    say STDERR "snapshot $table...";

    my $column_names = [ $db->query( <<END, $table, $key )->flat ];
select column_name from information_schema.columns 
    where table_name = ? and table_schema = 'cd' and
        column_name not in ( ? )
    order by ordinal_position asc
END

    die( "Field names can only have letters and underscores" ) if ( grep { /[^a-z_]/i } @{ $column_names } );
    die( "Table name can only have letters and underscores" ) if ( $table =~ /[^a-z_]/i );

    my $column_list = join( ",", @{ $column_names } );

    $db->query( <<END, $obj->{ $key } );
insert into cd.${ table } ( $column_list, $key ) select $column_list, ? from dump_${ table }
END

}

# create a snapshot of a table for a controversy_dump_time_slice
sub create_cdts_snapshot
{
    my ( $db, $cdts, $table ) = @_;

    create_snapshot( $db, $cdts, 'controversy_dump_time_slices_id', $table );
}

# create a snapshot of a table for a controversy_dump
sub create_cd_snapshot
{
    my ( $db, $cd, $table ) = @_;

    create_snapshot( $db, $cd, 'controversy_dumps_id', $table );
}

# generate temporary dump_* tables for the specified controversy_dump for each of the snapshot_tables.
# these are the tables that apply to the whole controversy_dump.
sub write_temporary_dump_tables
{
    my ( $db, $controversies_id ) = @_;

    set_temporary_table_tablespace();

    $db->query( <<END, $controversies_id );
create temporary table dump_controversy_stories $_temporary_tablespace as 
    select cs.*
        from controversy_stories cs
        where cs.controversies_id = ?
END

    $db->query( <<END, $controversies_id );
create temporary table dump_controversy_media_codes $_temporary_tablespace as 
    select cmc.*
        from controversy_media_codes cmc
        where cmc.controversies_id = ?
END

    $db->query( <<END, $controversies_id );
create temporary table dump_stories $_temporary_tablespace as
    select s.stories_id, s.media_id, s.url, s.guid, s.title, s.publish_date, s.collect_date, s.full_text_rss, s.language
        from cd.live_stories s
            join dump_controversy_stories dcs on ( s.stories_id = dcs.stories_id and s.controversies_id = ? )
END

    $db->query( <<END );
create temporary table dump_media $_temporary_tablespace as
    select m.* from media m
        where m.media_id in ( select media_id from dump_stories )
END

    $db->query( <<END, $controversies_id );
create temporary table dump_controversy_links_cross_media $_temporary_tablespace as
    select s.stories_id, r.stories_id ref_stories_id, cl.url, cs.controversies_id, cl.controversy_links_id
        from controversy_links cl
            join dump_controversy_stories cs on ( cs.stories_id = cl.ref_stories_id )
            join dump_stories s on ( cl.stories_id = s.stories_id )
            join dump_media sm on ( s.media_id = sm.media_id )
            join dump_stories r on ( cl.ref_stories_id = r.stories_id )
            join dump_media rm on ( r.media_id= rm.media_id )
        where cl.controversies_id = ? and r.media_id <> s.media_id
END

    $db->query( <<END );
create temporary table dump_stories_tags_map $_temporary_tablespace as
    select stm.*
    from stories_tags_map stm, dump_stories ds
    where stm.stories_id = ds.stories_id
END

    $db->query( <<END );
create temporary table dump_media_tags_map $_temporary_tablespace as
    select mtm.*
    from media_tags_map mtm, dump_media dm
    where mtm.media_id = dm.media_id
END

    $db->query( <<END );
create temporary table dump_tags $_temporary_tablespace as
    select distinct t.* from tags t where t.tags_id in
        ( select distinct a.tags_id
            from tags a
                join dump_media_tags_map amtm on ( a.tags_id = amtm.tags_id )
        
          union

          select distinct b.tags_id
            from tags b
                join dump_stories_tags_map bstm on ( b.tags_id = bstm.tags_id )
        )
     
END

    $db->query( <<END );
create temporary table dump_tag_sets $_temporary_tablespace as
    select ts.*
    from tag_sets ts
    where ts.tag_sets_id in ( select tag_sets_id from dump_tags )
END
}

# generate snapshots for all of the get_snapshot_tables from the temporary dump tables
sub generate_snapshots_from_temporary_dump_tables
{
    my ( $db, $cd ) = @_;

    my $snapshot_tables = get_snapshot_tables();

    map { create_cd_snapshot( $db, $cd, $_ ) } @{ $_snapshot_tables };
}

# create the controversy_dump row for the current dump
sub create_controversy_dump ($$$$)
{
    my ( $db, $controversy, $start_date, $end_date ) = @_;

    my $cd = $db->query( <<END, $controversy->{ controversies_id }, $start_date, $end_date )->hash;
insert into controversy_dumps 
    ( controversies_id, start_date, end_date, dump_date )
    values ( ?, ?, ?, now() )
    returning *
END

    $cd->{ controversy } = $controversy;

    return $cd;
}

# analyze all of the snapshot tables because otherwise immediate queries to the
# new dump ids offer trigger seq scans
sub analyze_snapshot_tables
{
    my ( $db ) = @_;

    print STDERR "analyzing tables...\n";

    my $snapshot_tables   = get_snapshot_tables();
    my $time_slice_tables = qw(story_links story_link_counts media_links media_link_counts);

    for my $t ( @{ $snapshot_tables } )
    {
        $db->query( "analyze cd.$t" );
    }
}

# validate and set the periods for the dump based on the period parameter
sub get_periods ($)
{
    my ( $period ) = @_;

    $period ||= 'all';

    my $all_periods = [ qw(custom overall weekly monthly) ];

    die( "period must be all, custom, overall, weekly, or monthly" )
      if ( $period && !grep { $_ eq $period } ( 'all', @{ $all_periods } ) );

    return ( $period eq 'all' ) ? $all_periods : [ $period ];
}

# get the tags associated with the controversy through controversy_dump_tags
sub get_dump_tags
{
    my ( $db, $controversy ) = @_;

    my $tags = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select distinct t.*
    from tags t
        join controversy_dump_tags cdt on ( t.tags_id = cdt.tags_id and cdt.controversies_id = ? )
END
}

# create a controversy_dump for the given controversy
sub dump_controversy ($$)
{
    my ( $db, $controversies_id ) = @_;

    my $periods = [ qw(custom overall weekly monthly) ];

    $db->dbh->{ PrintWarn } = 0;    # avoid noisy, extraneous postgres notices from drops

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "Unable to find controversy '$controversies_id'" );

    # Log activity that's about to start
    my $changes = {};
    unless (
        MediaWords::DBI::Activities::log_system_activity( $db, 'cm_dump_controversy', $controversies_id + 0, $changes ) )
    {
        die "Unable to log the 'cm_dump_controversy' activity.";
    }

    my ( $start_date, $end_date ) = get_default_dates( $db, $controversy );

    my $dump_tags = get_dump_tags( $db, $controversy );

    my $cd = create_controversy_dump( $db, $controversy, $start_date, $end_date );

    write_temporary_dump_tables( $db, $controversy->{ controversies_id } );
    generate_snapshots_from_temporary_dump_tables( $db, $cd );

    for my $t ( undef, @{ $dump_tags } )
    {
        for my $p ( @{ $periods } )
        {
            generate_period_dump( $db, $cd, $p, $t );
        }
    }

    write_date_counts_dump( $db, $cd, 'daily' );
    write_date_counts_dump( $db, $cd, 'weekly' );

    analyze_snapshot_tables( $db );

    # write_cleanup_dumps( $db, $controversy ) if ( $cleanup_data );
}

1;
