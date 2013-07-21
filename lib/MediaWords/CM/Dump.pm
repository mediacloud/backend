package MediaWords::CM::Dump;

# code to analyze a controversy and dump the controversy to snapshot tables and a gexf file

use strict;

use Data::Dumper;
use Date::Format;
use Encode;
use File::Temp;
use FileHandle;
use Getopt::Long;
use Statistics::Basic;
use XML::Simple;

use MediaWords::CM::Dump;
use MediaWords::DB;
use MediaWords::DBI::Media;
use MediaWords::Util::CSV;
use MediaWords::Util::Colors;
use MediaWords::Util::SQL;
use MediaWords::Util::Tags;

# percentage of media sources in a given dump for which to generate a confidence interval
use constant MODEL_PERCENT_TOP_MEDIA => 10;

# percentage of guessed dates that are misdated
use constant PERCENT_DATE_MISDATED => 22;

# percentages that a wrong date is wrong by the given number of days
use constant PERCENT_DATE_WRONG_BY_1    => 0;
use constant PERCENT_DATE_WRONG_BY_3    => 0;
use constant PERCENT_DATE_WRONG_BY_7    => 0;
use constant PERCENT_DATE_WRONG_BY_MORE => 100;

# percent of stories guessed to be undateable that are actually dateable
use constant PERCENT_UNDATEABLE_DATE_DATEABLE => 30;

# percent of stories guessed to be dateable that are actually undateable
use constant PERCENT_DATE_UNDATEABLE => 13;

# number of times to run the confidence model
use constant CONFIDENCE_REPS => 1;

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

# get the list of all snapshot tables
sub get_snapshot_tables
{
    return [ @{ $_snapshot_tables } ];
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

# period stories may be a view or a table, and postgres complains if we try to do
# a 'drop table|view if exits' if the object type doesn't match.  so we have to
# figure out if dump_period_stories exists and if so drop the appropriate
# object
sub drop_dump_period_stories
{
    my ( $db ) = @_;

    my $pg = $db->query( "select * from pg_class where relname = 'dump_period_stories'" )->hash;

    return unless ( $pg );

    my $kind = ( $pg->{ relkind } eq 'v' ) ? 'view' : 'table';

    $db->query( "drop $kind dump_period_stories" );
}

# write dump_period_stories table that holds list of all stories that should be included in the
# current period.  For an overall dump, every story should be in the current period.
# For other dumps, a story should be in the current dump if either its date is within
# the period dates or if a story that links to it has a date within the period dates.
# For this purpose, stories tagged with the 'date_guess_method:undateable' tag
# are considered to have an invalid tag, so their dates cannot be used to pass
# either of the above tests.
#
# The resulting dump_period_stories should be used by all other dump queries to determine
# story membership within a give period.
sub write_period_stories
{
    my ( $db, $cdts ) = @_;

    drop_dump_period_stories( $db );

    if ( !$cdts || ( $cdts->{ period } eq 'overall' ) )
    {
        $db->query( "create temporary view dump_period_stories as select stories_id from dump_stories" );
    }
    else
    {
        $db->query( <<END );
create or replace view dump_undateable_stories as
    select distinct s.stories_id
        from dump_stories s, dump_stories_tags_map stm, dump_tags t, dump_tag_sets ts
        where s.stories_id = stm.stories_id and
            stm.tags_id = t.tags_id and
            t.tag_sets_id = ts.tag_sets_id and
            ts.name = 'date_guess_method' and
            t.tag = 'undateable'
END

        $db->query( <<'END', $cdts->{ start_date }, $cdts->{ end_date } );
create temporary table dump_period_stories as
    select distinct s.stories_id
        from dump_stories s
            left join dump_controversy_links_cross_media cl on ( cl.ref_stories_id = s.stories_id )
            left join dump_stories ss on ( cl.stories_id = ss.stories_id )
        where 
            ( s.publish_date between $1::timestamp and $2::timestamp - interval '1 second' 
                and s.stories_id not in ( select stories_id from dump_undateable_stories ) ) or
            ( ss.publish_date between $1::timestamp and $2::timestamp - interval '1 second'
                and ss.stories_id not in ( select stories_id from dump_undateable_stories ) )
END

        $db->query( "drop view dump_undateable_stories" );
    }
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
	from dump_story_links sl, stories ss, media sm, stories rs, media rm
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

    update_cdts( $db, $cdts, 'story_links_csv', $csv );
}

sub write_story_links_dump
{
    my ( $db, $cdts, $is_model ) = @_;

    $db->query( "drop table if exists dump_story_links" );

    $db->query( <<END );
create temporary table dump_story_links as
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
select distinct s.stories_id, s.title, s.url, s.publish_date, 
        m.name media_name, m.url media_url, m.media_id,
        slc.inlink_count, slc.outlink_count $tag_clause_list
	from dump_stories s, dump_media m, dump_story_link_counts slc 
	where s.media_id = m.media_id and s.stories_id = slc.stories_id
	order by slc.inlink_count;
END

    return $csv;
}

sub write_stories_csv
{
    my ( $db, $cdts ) = @_;

    my $csv = get_stories_csv( $db, $cdts );

    update_cdts( $db, $cdts, 'stories_csv', $csv );
}

sub write_story_link_counts_dump
{
    my ( $db, $cdts, $is_model ) = @_;

    $db->query( "drop table if exists dump_story_link_counts" );

    $db->query( <<END );
create temporary table dump_story_link_counts as
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
  where t.tag_sets_id = ts.tag_sets_id and ts.name = ? and t.tag <> 'all' and
    exists ( select 1 from dump_stories_tags_map stm, dump_story_link_counts slc 
                 where stm.tags_id = t.tags_id and slc.stories_id = stm.stories_id )
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
    my ( $db, $controversy, $media ) = @_;

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

    update_cdts( $db, $cdts, 'media_csv', $csv );
}

sub write_medium_link_counts_dump
{
    my ( $db, $cdts, $is_model ) = @_;

    $db->query( "drop table if exists dump_medium_link_counts" );

    $db->query( <<END );
create temporary table dump_medium_link_counts as   
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

    update_cdts( $db, $cdts, 'medium_links_csv', $csv );
}

sub write_medium_links_dump
{
    my ( $db, $cdts, $is_model ) = @_;

    $db->query( "drop table if exists dump_medium_links" );

    $db->query( <<END );
create temporary table dump_medium_links as
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

    $db->update_by_id( 'controversy_dumps', $cd->{ controversy_dumps_id }, { "${ period }_counts_csv" => $csv } );
}

sub write_date_counts_dump
{
    my ( $db, $cd, $period ) = @_;

    die( "unknown period '$period'" ) unless ( grep { $period eq $_ } qw(daily weekly) );
    my $date_trunc = ( $period eq 'daily' ) ? 'day' : 'week';

    $db->query( <<END, $date_trunc, $date_trunc );
create temporary table dump_${ period }_date_counts as
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
"java -cp $FindBin::Bin/../java/build/jar/GephiLayout.jar:FindBin::Bin/../java/lib/gephi-toolkit.jar edu.law.harvard.cyber.mediacloud.layout.GephiLayout $nolayout_path $layout_path";

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

    update_cdts( $db, $cdts, 'gexf', $layout_gexf );
}

# return true if there are any stories in the current controversy_stories_dump_ table
sub stories_exist_for_period
{
    my ( $db, $controversy ) = @_;

    return $db->query( "select 1 from dump_stories" )->hash;
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

sub create_controversy_dump_time_slice ($$$$$)
{
    my ( $db, $cd, $start_date, $end_date, $period ) = @_;

    my $cdts = $db->query( <<END, $cd->{ controversy_dumps_id }, $start_date, $end_date, $period )->hash;
insert into controversy_dump_time_slices
    ( controversy_dumps_id, start_date, end_date, period )
    values ( ?, ?, ?, ? )
    returning *
END

    $cdts->{ controversy_dump } = $cd;

    return $cdts;
}

# generate data for the story_links, story_link_counts, media_links, media_link_counts tables
# based on the data in the temporary dump_* tables
sub generate_period_dump_data ($$;$)
{
    my ( $db, $cdts, $is_model ) = @_;

    write_period_stories( $db, $cdts );
    write_story_link_counts_dump( $db, $cdts, $is_model );
    write_story_links_dump( $db, $cdts, $is_model );

    return unless ( stories_exist_for_period( $db, $cdts ) );

    write_medium_link_counts_dump( $db, $cdts, $is_model );
    write_medium_links_dump( $db, $cdts, $is_model );
}

# get the top MODEL_PERCENT_TOP_MEDIA of media sources from the current dump by incoming links
sub get_top_media_link_counts
{
    my ( $db, $cdts, $size_factor ) = @_;

    my ( $num_media ) = $db->query( "select count(*) from dump_medium_link_counts" )->flat;

    return [] unless ( $num_media > 0 );

    my $num_top_media = POSIX::ceil( $num_media * ( MODEL_PERCENT_TOP_MEDIA / 100 ) );
    $num_top_media *= $size_factor if ( $size_factor );

    my $top_media = $db->query( <<END, $num_top_media + 1 )->hashes;
select * from dump_medium_link_counts order by inlink_count desc limit ?
END

    # the last medium included must have more inlinks than the first medium not included
    my $first_miss_medium = pop( @{ $top_media } );
    my $min_inlink_count  = $first_miss_medium->{ inlink_count } + 1;
    my $pruned_top_media  = [ grep { $_->{ inlink_count } > $min_inlink_count } @{ $top_media } ];

    return $pruned_top_media;
}

# change a dateable story to an undateable one
sub tweak_dateable_story
{
    my ( $db, $cdts, $story ) = @_;

    # print "tweak_dateable_story: $story->{ stories_id }\n";

    my $undateable_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:undateable' );

    $db->query( <<END, $story->{ stories_id }, $undateable_tag->{ tags_id } );
insert into dump_stories_tags_map
    ( stories_id, tags_id )
    values ( ?, ? )
END

}

# get random sample of stories with guessed dates
sub sample_guessed_date_stories
{
    my ( $db, $cdts, $percent_sample ) = @_;

    my $stories = $db->query( <<END, $percent_sample )->hashes;
select * from  
(
    select s.*
        from dump_stories s, dump_tags t, dump_tag_sets ts, dump_stories_tags_map stm 
        where s.stories_id = stm.stories_id and 
            t.tags_id = stm.tags_id and 
            t.tag_sets_id = ts.tag_sets_id and 
            ts.name = 'date_guess_method' and 
            t.tag not in ( 'manual', 'merged_story_rss', 'guess_by_url_and_date_text', 'guess_by_url' )

    except

    select s.*
        from dump_stories s, dump_tags t, dump_tag_sets ts, dump_stories_tags_map stm 
        where s.stories_id = stm.stories_id and 
            t.tags_id = stm.tags_id and 
            t.tag_sets_id = ts.tag_sets_id and 
            ts.name = 'date_guess_method' and 
            t.tag = 'undateable'
) q
    where ( random() *  100 ) < ?
END

    return $stories;

}

# change dated stories to be undateable based on our data on how many
# dated stories are undateable
sub tweak_dateable_stories
{
    my ( $db, $cdts ) = @_;

    my $stories = sample_guessed_date_stories( $db, $cdts, PERCENT_DATE_UNDATEABLE );

    map { tweak_dateable_story( $db, $cdts, $_ ) } @{ $stories };
}

# change an undateable story to a dateable one by deleting the date_guess_method:undateable tag
sub tweak_undateable_story
{
    my ( $db, $cdts, $story ) = @_;

    # print "tweak_undateable_story: $story->{ stories_id }\n";

    $db->query( <<END, $story->{ stories_id } );
delete from dump_stories_tags_map stm
    using dump_tags t, dump_tag_sets ts
    where stm.stories_id =? and
        stm.tags_id = t.tags_id and 
        t.tag_sets_id = ts.tag_sets_id and
        ts.name = 'date_guess_method' and
        t.tag = 'undateable'
END
}

# change undateable stories to dateable ones according to our data
# on how many undateable stories are really dateable
sub tweak_undateable_stories
{
    my ( $db, $cdts ) = @_;

    my $stories = $db->query( <<END, PERCENT_UNDATEABLE_DATE_DATEABLE )->hashes;
select * from
(
    select s.* 
        from dump_stories s, dump_tags t, dump_tag_sets ts, dump_stories_tags_map stm 
        where s.stories_id = stm.stories_id and 
            t.tags_id = stm.tags_id and 
            t.tag_sets_id = ts.tag_sets_id and 
            ts.name = 'date_guess_method' and 
            t.tag = 'undateable'
            
    except
    
    select s.*
        from dump_stories s, dump_tags t, dump_tag_sets ts, dump_stories_tags_map stm 
        where s.stories_id = stm.stories_id and 
            t.tags_id = stm.tags_id and 
            t.tag_sets_id = ts.tag_sets_id and 
            ts.name = 'date_guess_method' and 
            t.tag = 'manual'
) q
    where ( random() *  100 ) < ?

END

    map { tweak_undateable_story( $db, $cdts, $_ ) } @{ $stories };
}

# get the new story date according to our validation data of how dates
# are typically wrong
sub get_tweaked_story_date
{
    my ( $old_date ) = @_;

    my $past = ( rand( 2 ) < 1 ) ? -1 : 1;

    # roll a die to see how wrong the date is, according to stats about wrong date distribution
    my $wrong_by_dist = rand( 100 );

    my $new_date;
    if ( $wrong_by_dist < PERCENT_DATE_WRONG_BY_1 )
    {
        return MediaWords::Util::SQL::increment_day( $old_date, $past );
    }
    $wrong_by_dist -= PERCENT_DATE_WRONG_BY_1;

    if ( $wrong_by_dist < PERCENT_DATE_WRONG_BY_3 )
    {
        my $days = POSIX::ceil( rand( 2 ) ) + 1;
        return MediaWords::Util::SQL::increment_day( $old_date, $past * $days );
    }
    $wrong_by_dist -= PERCENT_DATE_WRONG_BY_3;

    if ( $wrong_by_dist < PERCENT_DATE_WRONG_BY_7 )
    {
        my $days = POSIX::ceil( rand( 4 ) ) + 3;
        return MediaWords::Util::SQL::increment_day( $old_date, $past * $days );
    }

    my $days = POSIX::ceil( rand( 53 ) + 7 );
    return MediaWords::Util::SQL::increment_day( $old_date, $past * $days );
}

# change the story date according to our validation data of how dates are
# typically wrong
sub tweak_story_date
{
    my ( $db, $cdts, $story ) = @_;

    my $new_date = get_tweaked_story_date( $story->{ publish_date } );

    # print "tweak story: $story->{ stories_id } $story->{ publish_date } -> $new_date\n";

    $db->query( <<END, $new_date, $story->{ stories_id } );
update dump_stories set publish_date = ? where stories_id = ?
END

}

# chagne the dates of stories according to our data of how often guess dates
# are wrong
sub tweak_misdated_stories
{
    my ( $db, $cdts ) = @_;

    my $stories = sample_guessed_date_stories( $db, $cdts, PERCENT_DATE_MISDATED );

    map { tweak_story_date( $db, $cdts, $_ ) } @{ $stories };
}

# change the dates in the current dump to model the accuracy data form our validation tests
sub tweak_story_dates
{
    my ( $db, $cdts ) = @_;

    $db->begin;

    tweak_misdated_stories( $db, $cdts );
    tweak_undateable_stories( $db, $cdts );
    tweak_dateable_stories( $db, $cdts );

    $db->commit;
}

# generate a single model of the dump for the current time slice, tweaking
# various aspects of the data according to our validation numbers (for example
# changing X% of dates because we know that in general X% of our dates are wrong).
# Return an ordered list of the top media sources by incoming links.
sub model_confidence_data
{
    my ( $db, $cdts ) = @_;

    tweak_story_dates( $db, $cdts );

    generate_period_dump_data( $db, $cdts, 1 );

    my $top_media_link_counts = get_top_media_link_counts( $db, $cdts, 2 );

    return $top_media_link_counts;
}

# given an ordered list of medium_counts, return a hash with the media_id of each
# as the key and the order in the list as the value
sub get_medium_count_ranks
{
    my ( $media_counts ) = @_;

    my $ranks = {};
    for ( my $i = 0 ; $i < @{ $media_counts } ; $i++ )
    {
        $ranks->{ $media_counts->[ $i ]->{ media_id } } = $i;
    }

    return $ranks;
}

# return true if the two ranks are within the error interval of each other.  Assume a max
# rank of $max_rank for the $model_rank.
sub model_rank_within_error_interval
{
    my ( $clean_rank, $model_rank ) = @_;

    return 0 unless ( defined( $model_rank ) );

    my $interval = POSIX::ceil( $clean_rank / 3 ) + 2;

    return ( abs( $clean_rank - $model_rank ) <= $interval );
}

# given the size of two vectors and the r, return the p value for the correlation
sub get_model_correlation_p_value
{
    my ( $clean_vector, $model_vector, $r ) = @_;

    my $p_hits   = 0;
    my $num_reps = 10000;
    for my $i ( 1 .. $num_reps )
    {
        my $randomized_model = [ List::Util::shuffle( @{ $model_vector } ) ];

        my $p_r = Statistics::Basic::correlation( $clean_vector, $randomized_model );

        $p_hits++ if ( $p_r >= $r );
    }

    return ( $p_hits / $num_reps );
}

# return the correlation between the clean data repeated CONFIDENCE_REPS times and
# the concatenation of all models
sub update_model_correlation
{
    my ( $db, $cdts, $all_models_top_media ) = @_;

    my $clean_top_media = get_top_media_link_counts( $db, $cdts );

    update_cdts( $db, $cdts, 'model_num_media', scalar( @{ $clean_top_media } ) );

    return unless ( @{ $clean_top_media } > 1 );

    my $clean_vector = [];
    for ( my $i = 0 ; $i < @{ $clean_top_media } ; $i++ )
    {
        push( @{ $clean_vector }, $i );
    }

    my $model_r2s = [];
    for my $model_top_media ( @{ $all_models_top_media } )
    {
        my $model_medium_ranks = get_medium_count_ranks( $model_top_media );
        my $model_vector       = [];
        for my $clean_top_medium ( @{ $clean_top_media } )
        {
            my $model_medium_rank = $model_medium_ranks->{ $clean_top_medium->{ media_id } };
            $model_medium_rank = scalar( @{ $model_top_media } + 1 ) unless ( defined( $model_medium_rank ) );
            push( @{ $model_vector }, $model_medium_rank );
        }

        my $r = Statistics::Basic::correlation( $clean_vector, $model_vector );
        push( @{ $model_r2s }, $r * $r );
    }

    my $r2_mean   = Statistics::Basic::mean( $model_r2s );
    my $r2_stddev = Statistics::Basic::stddev( $model_r2s );

    update_cdts( $db, $cdts, 'model_r2_mean',   $r2_mean );
    update_cdts( $db, $cdts, 'model_r2_stddev', $r2_stddev );
}

# return text output describing how the models matched (or didn't) with the clean data
sub print_model_matches
{
    my ( $db, $cdts, $all_models_top_media ) = @_;

    my $clean_top_media = get_top_media_link_counts( $db, $cdts );
    my $clean_medium_ranks = get_medium_count_ranks( $clean_top_media );

    print "evaluating models ...\n";

    my $num_model_matches = 0;
    for my $model_top_media ( @{ $all_models_top_media } )
    {
        my $match              = 1;
        my $model_medium_ranks = get_medium_count_ranks( $model_top_media );
        while ( my ( $clean_media_id, $clean_rank ) = each( %{ $clean_medium_ranks } ) )
        {
            my $model_rank = $model_medium_ranks->{ $clean_media_id };
            if ( model_rank_within_error_interval( $clean_rank, $model_rank ) )
            {
                print "+";
            }
            else
            {
                print "-";
                print "[ $clean_media_id: $clean_rank / $model_rank ]";
                $match = 0;
            }
        }
        print "\n";

        $num_model_matches++ if ( $match );
    }

    # update_cdts( $db, $cdts, 'confidence', $num_model_matches );
    #
    # return $num_model_matches;
}

# generate the dumps for the given period and dates
sub generate_period_dump ($$$$$)
{
    my ( $db, $cd, $start_date, $end_date, $period ) = @_;

    my $cdts = create_controversy_dump_time_slice( $db, $cd, $start_date, $end_date, $period );

    my $dump_label = "${ period }: ${ start_date } - ${ end_date }";
    print "generating $dump_label ...\n";

    print "copying temporary tables ...\n";
    copy_temporary_tables( $db );

    print "running models: ";
    my $all_models_top_media = [];
    for my $i ( 1 .. CONFIDENCE_REPS )
    {

        # these make the data tweaking process and other operations much faster
        $db->query( "create index dump_stories_story on dump_stories ( stories_id )" );
        $db->query( "create index dump_tags_tag on dump_tags ( tags_id )" );
        $db->query( "create index dump_stories_tags_map_story on dump_stories_tags_map ( stories_id )" );

        push( @{ $all_models_top_media }, model_confidence_data( $db, $cdts ) );
        print ".";
        restore_temporary_tables( $db );
    }

    print "\ngenerating dump data ...\n";
    generate_period_dump_data( $db, $cdts );

    print_model_matches( $db, $cdts, $all_models_top_media );

    update_model_correlation( $db, $cdts, $all_models_top_media );

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
sub generate_custom_period_dumps ($$)
{
    my ( $db, $cd ) = @_;

    my $controversy_dates = $db->query( <<END, $cd->{ controversies_id } )->hashes;
select * from controversy_dates where controversies_id = ? order by start_date, end_date
END

    for my $controversy_date ( @{ $controversy_dates } )
    {
        my $start_date = $controversy_date->{ start_date };
        my $end_date   = $controversy_date->{ end_date };
        generate_period_dump( $db, $cd, $start_date, $end_date, 'custom' );
    }
}

# generate dumps for the given period (overall, monthly, weekly, or custom)
sub generate_all_period_dumps ($$$)
{
    my ( $db, $cd, $period ) = @_;

    my $start_date = $cd->{ start_date };
    my $end_date   = $cd->{ end_date };

    if ( $period eq 'overall' )
    {
        generate_period_dump( $db, $cd, $start_date, $end_date, $period );
    }
    elsif ( $period eq 'weekly' )
    {
        my $w_start_date = truncate_to_monday( $start_date );
        while ( $w_start_date lt $end_date )
        {
            my $w_end_date = MediaWords::Util::SQL::increment_day( $w_start_date, 7 );

            generate_period_dump( $db, $cd, $w_start_date, $w_end_date, $period );

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

            generate_period_dump( $db, $cd, $m_start_date, $m_end_date, $period );

            $m_start_date = $m_end_date;
        }
    }
    elsif ( $period eq 'custom' )
    {
        generate_custom_period_dumps( $db, $cd );
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

    my ( $start_date, $end_date ) = $db->query( <<END, $controversy->{ query_story_searches_id } )->flat;
select q.start_date, q.end_date from queries q, query_story_searches qss
    where qss.query_story_searches_id = ? and q.queries_id = qss.queries_id
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
        $db->query( "create temporary table $copy_table as select * from $dump_table" );
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
        $db->query( "create temporary table $dump_table as select * from $copy_table" );
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

    $db->query( <<END, $controversies_id );
create temporary table dump_controversy_links_cross_media as
    select cl.*
        from controversy_links_cross_media cl
        where cl.controversies_id = ?
END

    $db->query( <<END, $controversies_id );
create temporary table dump_controversy_stories as 
    select cs.*
        from controversy_stories cs
        where cs.controversies_id = ?
END

    $db->query( <<END, $controversies_id );
create temporary table dump_controversy_media_codes as 
    select cmc.*
        from controversy_media_codes cmc
        where cmc.controversies_id = ?
END

    $db->query( <<END );
create temporary table dump_stories as
    select s.*
        from stories s, dump_controversy_stories dcs
        where s.stories_id = dcs.stories_id
END

    $db->query( <<END );
create temporary table dump_media as
    select distinct m.* 
        from media m, dump_stories ds
        where ds.media_id = m.media_id
END

    $db->query( <<END );
create temporary table dump_stories_tags_map as
    select distinct stm.*
    from stories_tags_map stm, dump_stories ds
    where stm.stories_id = ds.stories_id
END

    $db->query( <<END );
create temporary table dump_media_tags_map as
    select distinct mtm.*
    from media_tags_map mtm, dump_media dm
    where mtm.media_id = dm.media_id
END

    $db->query( <<END );
create temporary table dump_tags as
    select t.*
    from tags t
    where t.tags_id in ( select tags_id from dump_media_tags_map ) or
        t.tags_id in ( select tags_id from dump_stories_tags_map )
END

    $db->query( <<END );
create temporary table dump_tag_sets as
    select ts.*
    from tag_sets ts
    where ts.tag_sets_id in ( select tag_sets_id from dump_tags )
END
}

# generate snapshots for all of the get_snapshot_tables from the temporary dump tables
sub generate_snapshots_from_temporary_dump_tables
{
    my ( $db, $cd, $start_date, $end_date ) = @_;

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
        $db->query( "analyze $t" );
    }
}

# create a controversy_dump for the given controversy, start_date, end_date, and period
sub dump_controversy ($$$$$)
{
    my ( $db, $controversies_id, $start_date, $end_date, $period ) = @_;

    $| = 1;

    $period ||= 'all';

    my $all_periods = [ qw(custom overall weekly monthly) ];

    die( "period must be all, custom, overall, weekly, or monthly" )
      if ( $period && !grep { $_ eq $period } ( 'all', @{ $all_periods } ) );

    # we do lots of dropping tables and views that produce noisy, extraneous postgres notices
    $db->dbh->{ PrintWarn } = 0;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "Unable to find controversy '$controversies_id'" );

    if ( !$start_date || !$end_date )
    {
        my ( $default_start_date, $default_end_date ) = get_default_dates( $db, $controversy );
        $start_date ||= $default_start_date;
        $end_date   ||= $default_end_date;
    }

    my $cd = create_controversy_dump( $db, $controversy, $start_date, $end_date );

    write_temporary_dump_tables( $db, $controversy->{ controversies_id } );
    generate_snapshots_from_temporary_dump_tables( $db, $cd, $start_date, $end_date );

    my $periods = ( $period eq 'all' ) ? $all_periods : [ $period ];

    for my $p ( @{ $periods } )
    {
        generate_all_period_dumps( $db, $cd, $p );
    }

    write_date_counts_dump( $db, $cd, 'daily' );
    write_date_counts_dump( $db, $cd, 'weekly' );

    analyze_snapshot_tables( $db );

    # write_cleanup_dumps( $db, $controversy ) if ( $cleanup_data );
}

1;
