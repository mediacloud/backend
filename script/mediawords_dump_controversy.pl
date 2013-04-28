#!/usr/bin/env perl

# dump various controversy queries to csv and build a gexf file

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Carp;
use Color::Mix;
use Data::Dumper;
use Date::Format;
use Encode;
use File::Path;
use Getopt::Long;
use XML::Simple;

use MediaWords::DB;
use MediaWords::DBI::Media;
use MediaWords::Util::CSV;
use MediaWords::Util::Colors;
use MediaWords::Util::SQL;

# max and mind node sizes for gexf dump
use constant MAX_NODE_SIZE => 50;
use constant MIN_NODE_SIZE => 5;

# max map width for gexf dump
use constant MAX_MAP_WIDTH => 800;

my $_num_similar_stories_per_story = 10;

# consistent colors for media types
my $_media_type_color_map;

# globals for tracking dump info
my $_dump_version;
my $_dump_label;
my $_dump_media;

# attributes to include in gexf dump
my $_media_static_gexf_attribute_types = {
    url         => 'string',
    link_weight => 'float',
    link_count  => 'integer',
    story_count => 'integer',
};

# track the paths of all layout dumps so that we can write them to
# an html file at the end of the dump process
my $_layout_dump_paths;

# parent dir to store all the dumps in.  keep track of this in a static so that
# we can create a new one for each dump one by iterating until we find a directory
# that already exists (but we have to be able to call get_parent_dump_dir multiple
# times in this script)
my $_parent_dump_dir;

sub set_dump_label
{
    ( $_dump_label ) = @_;
}

sub get_dump_label
{
    return $_dump_label;
}

# get the root dir for all of this run of dumps
sub get_parent_dump_dir
{
    my ( $controversy ) = @_;

    return $_parent_dump_dir if ( $_parent_dump_dir );

    my $controversy_name = $controversy->{ name };
    $controversy_name =~ s/\//_/g;

    my $parent_dump_dir;
    my $i = 1;
    do
    {
        $parent_dump_dir =
          "controversy_dumps/${ controversy_name }_dumps_" . Date::Format::time2str( '%Y-%m-%d', time ) . "_" . $i++;
    } while ( -e $parent_dump_dir );

    File::Path::mkpath( $parent_dump_dir ) unless ( -e $parent_dump_dir );

    $_parent_dump_dir = $parent_dump_dir;

    print STDERR "dump dir: $parent_dump_dir\n";

    return $parent_dump_dir;
}

# append the dump label to the dump file name, add the extension, and prepend the dump dir
sub get_dump_file_path
{
    my ( $controversy, $file_name, $extension ) = @_;

    my $dump_label = get_dump_label();

    my $parent_dump_dir = get_parent_dump_dir( $controversy );

    my $dump_dir = "$parent_dump_dir/controversy_dump_${ dump_label }";
    mkdir( $dump_dir ) unless ( -d $dump_dir );

    my $file_path = "$dump_dir/${ file_name }_${ dump_label }.${ extension }";

    return $file_path;
}

# append the dump label to the dump file name, add the extension, and write to the dump dir
sub write_dump_file
{
    my ( $controversy, $file_name, $extension, $encoded_data ) = @_;

    my $file_path = get_dump_file_path( $controversy, $file_name, $extension );

    open( FILE, ">$file_path" ) || die( "Unable to open dump file '$file_path': $!" );

    print FILE $encoded_data;

    close( FILE );

    return $file_path;

}

# write the dump as a csv
sub write_dump_as_csv
{
    my ( $db, $controversy, $table, $query ) = @_;

    replace_table_contents( $db, $table, $query );

    my $dump_version = get_dump_version( $db );

    my $res = $db->query( "select * from ${ table }_${ dump_version }" );

    my $fields = $res->columns;

    my $data = $res->hashes;

    my $csv_string = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $data, $fields );

    write_dump_file( $controversy, $table, 'csv', $csv_string );
}

sub write_link_counts
{
    my ( $db, $controversy, $start_date, $end_date ) = @_;

    replace_table_contents( $db, 'controversy_story_link_counts_dump',
        "select count(distinct cl.stories_id) link_count, ref_stories_id " .
          "  from controversy_links_cross_media cl, stories s, stories r " .
          "  where cl.stories_id = s.stories_id and cl.ref_stories_id = r.stories_id and " .
          "    ( s.publish_date between '$start_date'::timestamp and '$end_date'::timestamp - interval '1 second' ) and " .
          "    s.publish_date > r.publish_date - interval '1 day' and " .
          "    controversies_id = $controversy->{ controversies_id } " . "  group by ref_stories_id" );

    replace_table_contents( $db, 'controversy_story_outlink_counts_dump',
        "select count(distinct cl.ref_stories_id) outlink_count, cl.stories_id " .
          "  from controversy_links_cross_media cl, stories s, stories r " .
          "  where cl.stories_id = s.stories_id and cl.ref_stories_id = r.stories_id and " .
          "    ( s.publish_date between '$start_date'::timestamp and '$end_date'::timestamp - interval '1 second' ) and " .
"    cl.controversies_id = $controversy->{ controversies_id } and s.publish_date > r.publish_date - interval '1 day' "
          . "  group by cl.stories_id" );
}

sub write_controversy_stories_dump
{
    my ( $db, $controversy, $start_date, $end_date ) = @_;

    my $tagset_name = "Controversy $controversy->{ name }";

    my $tags = $db->query(
        "select * from tags t, tag_sets ts " . "  where t.tag_sets_id = ts.tag_sets_id and ts.name = ? and t.tag <> 'all'",
        $tagset_name )->hashes;

    my $tag_clauses = [];
    for my $tag ( @{ $tags } )
    {
        my $label = "tagged_" . $tag->{ tag };

        push(
            @{ $tag_clauses },
            "exists ( select 1 from stories_tags_map stm " .
              "  where s.stories_id = stm.stories_id and stm.tags_id = $tag->{ tags_id } ) $label "
        );
    }

    my $tag_clause_list = join( ',', @{ $tag_clauses } );
    $tag_clause_list = ", $tag_clause_list" if ( $tag_clause_list );

    my $dump_version = get_dump_version( $db );

    my $cid = $controversy->{ controversies_id };

    write_dump_as_csv( $db, $controversy, 'controversy_stories_dump', <<END );
select distinct s.stories_id, s.title, s.url, s.publish_date, 
        m.name media_name, m.url media_url, m.media_id, cs.link_weight, 
        coalesce( lc.link_count, 0) link_count,  coalesce( olc.outlink_count, 0) outlink_count, 
        coalesce( lc.link_count, 0) + coalesce( olc.outlink_count, 0) total_link_count $tag_clause_list
	from stories s, media m, controversy_stories cs  
	    left join controversy_story_link_counts_dump_${ dump_version } as lc on ( cs.stories_id = lc.ref_stories_id )
	    left join controversy_story_outlink_counts_dump_${ dump_version } as olc on ( cs.stories_id = olc.stories_id )
	where cs.stories_id = s.stories_id and s.media_id = m.media_id and cs.controversies_id = $cid and 
        ( s.stories_id in ( 
            ( select cl.source_stories_id from controversy_links_dump_${ dump_version } cl ) union
            ( select cl.ref_stories_id from controversy_links_dump_${ dump_version } cl ) ) 
          or s.publish_date between '$start_date'::timestamp and '$end_date'::timestamp - interval '1 second' )
	order by s.publish_date;
END
}

sub write_controversy_links_dump
{
    my ( $db, $controversy, $start_date, $end_date ) = @_;

    write_dump_as_csv( $db, $controversy, 'controversy_links_dump', <<END );
select distinct cl.stories_id source_stories_id, ss.title source_title, ss.url source_url, 
        sm.name source_media_name, sm.url source_media_url, sm.media_id source_media_id,
		cl.ref_stories_id ref_stories_id, rs.title ref_title, rs.url ref_url, rm.name ref_media_name, rm.url ref_media_url, 
		rm.media_id ref_media_id
	from controversy_links_cross_media cl, stories ss, media sm, stories rs, media rm
	where cl.stories_id = ss.stories_id and ss.media_id = sm.media_id and cl.ref_stories_id = rs.stories_id and rs.media_id = rm.media_id and 
	  ( ss.publish_date between '$start_date'::timestamp and '$end_date'::timestamp - interval '1 second' ) and
      ss.publish_date > rs.publish_date - interval '1 day' and
	  cl.controversies_id = $controversy->{ controversies_id }
END
}

sub add_tags_to_dump_media
{
    my ( $db, $controversy, $media ) = @_;

    my $tagset_name = "controversy_$controversy->{ name }";

    my $tags = $db->query(
        "select * from tags t, tag_sets ts " .
          "  where t.tag_sets_id = ts.tag_sets_id and ts.name = ? and t.tag <> 'all' and " .
          "    exists ( select 1 from stories_tags_map stm where stm.tags_id = t.tags_id )",
        $tagset_name
    )->hashes;

    my $tag_fields = [];
    for my $tag ( @{ $tags } )
    {
        my $label = "tagged_" . $tag->{ tag };

        push( @{ $tag_fields }, $label );

        my $media_tags = $db->query(
"select s.media_id, stm.* from stories s, stories_tags_map stm where s.stories_id = stm.stories_id and stm.tags_id = ?",
            $tag->{ tags_id }
        )->hashes;

        my $media_tags_map = {};
        map { $media_tags_map->{ $_->{ media_id } } += 1 } @{ $media_tags };

        map { $_->{ $label } = $media_tags_map->{ $_->{ media_id } } || 0 } @{ $media };
    }

    return $tag_fields;
}

sub add_codes_to_dump_media
{
    my ( $db, $controversy, $media ) = @_;

    my $code_types = $db->query( "select distinct code_type from controversy_media_codes where controversies_id = ?",
        $controversy->{ controversies_id } )->flat;

    my $code_fields = [];
    for my $code_type ( @{ $code_types } )
    {
        my $label = "code_" . $code_type;

        push( @{ $code_fields }, $label );

        my $media_codes = $db->query( "select * from controversy_media_codes where controversies_id = ? and code_type = ?",
            $controversy->{ controversies_id }, $code_type )->hashes;

        my $media_codes_map = {};
        map { $media_codes_map->{ $_->{ media_id } } = $_->{ code } } @{ $media_codes };

        map { $_->{ $label } = $media_codes_map->{ $_->{ media_id } } || 'null' } @{ $media };
    }

    return $code_fields;
}

sub write_controversy_media_dump
{
    my ( $db, $controversy ) = @_;

    my $dump_version = get_dump_version( $db );

    my $res = $db->query( <<END );
select m.media_id, m.name, m.url, min( ssd.publish_date ) start_date, max( ssd.publish_date ) end_date,
        sum( ssd.link_count) link_count, sum( ssd.outlink_count) outlink_count,
        sum( ssd.total_link_count ) total_link_count, sum( ssd.link_weight ) link_weight, 
        count(*) story_count
  from media m join controversy_stories_dump_${ dump_version } ssd on ( ssd.media_id = m.media_id )
  group by m.media_id, m.name, m.url
  order by sum( ssd.link_weight );    
END

    my $fields = $res->columns;
    my $media  = $res->hashes;

    my $code_fields = add_codes_to_dump_media( $db, $controversy, $media );
    my $tag_fields = add_tags_to_dump_media( $db, $controversy, $media );

    push( @{ $fields }, @{ $code_fields } );
    push( @{ $fields }, @{ $tag_fields } );

    my $csv_string = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $media, $fields );

    write_dump_file( $controversy, 'controversy_media_dump', 'csv', $csv_string );

    $_dump_media = $media;
}

sub write_controversy_media_links_dump
{
    my ( $db, $controversy ) = @_;

    my $dump_version = get_dump_version( $db );

    write_dump_as_csv( $db, $controversy, 'controversy_media_links_dump', <<END );
select source_media_id, ref_media_id, count(*) link_count
  from controversy_links_dump_${ dump_version } group by source_media_id, ref_media_id
END
}

# get the list of fields and subqueries to include in the date count query
# for each tag in the controversy_<name> tag_set
sub get_date_count_tag_queries
{
    my ( $db, $controversy, $period ) = @_;

    my $tagset_name = "controversy_$controversy->{ name }";

    my $tags = $db->query( <<END, $tagset_name )->hashes;
select * from tags t, tag_sets ts  where t.tag_sets_id = ts.tag_sets_id and ts.name = ?
END

    return unless ( @{ $tags } );

    my $tag_fields  = [];
    my $tag_queries = [];
    my $labels_map  = {};

    for my $tag ( @{ $tags } )
    {
        my $label = "c_" . $tag->{ tag };

        $label = substr( $label, 0, 61 ) if ( length( $label ) > 61 );
        my $i = 1;
        while ( $labels_map->{ $label } )
        {
            substr( $label, -4 ) = "_" . $i++;
        }

        $labels_map->{ $label } = 1;

        push( @{ $tag_fields }, "coalesce( $label.date_count, 0 ) d_$label" );

        push(
            @{ $tag_queries },
            "left join ( select count(*) date_count,  date_trunc( '$period', a.publish_date ) publish_date " .
              "      from stories_tags_map stm, stories a " .
              "      where a.stories_id = stm.stories_id and stm.tags_id = $tag->{ tags_id } " .
              "      group by date_trunc( '$period', a.publish_date ) ) " .
              "  as $label on ( all_dates.publish_date = $label.publish_date )"
        );
    }

    return ( $tag_fields, $tag_queries );
}

sub write_controversy_date_counts_dump
{
    my ( $db, $controversy, $start_date, $end_date, $period ) = @_;

    die( "unknown period '$period'" ) unless ( grep { $period eq $_ } qw(day week) );

    my ( $tag_fields, $tag_queries ) = get_date_count_tag_queries( $db, $controversy, $period );

    return unless ( $tag_fields );

    my $tag_fields_list  = join( ', ', @{ $tag_fields } );
    my $tag_queries_list = join( ' ',  @{ $tag_queries } );

    my $cid = $controversy->{ controversies_id };

    write_dump_as_csv( $db, $controversy, 'controversy_' . $period . '_date_counts_dump', <<END );
select all_dates.publish_date, $tag_fields_list
    from ( select distinct date_trunc( '$period', s.publish_date ) publish_date
             from stories s join controversy_stories cs on ( s.stories_id = cs.stories_id and controversies_id = $cid ) ) all_dates
         $tag_queries_list
         where all_dates.publish_date between '$start_date'::timestamp and '$end_date'::timestamp - interval '1 second'
         order by all_dates.publish_date
END
}

sub get_dump_version
{
    my ( $db ) = @_;

    return $_dump_version if ( $_dump_version );

    my $last_media_dump = $db->query(
"select tablename from pg_tables where tablename like 'controversy_story_link_counts_dump_%' order by tablename desc limit 1"
    )->hash;

    if ( $last_media_dump )
    {
        $last_media_dump->{ tablename } =~ /(\d+)$/
          || die( "Can't parse media dump table name: '$last_media_dump->{ tablename }'" );
        my $version = $1;

        $_dump_version = sprintf( "%06d", $version + 1 );
    }
    else
    {
        $_dump_version = sprintf( "%06d", 1 );
    }

    return $_dump_version;
}

sub replace_table_contents
{
    my ( $db, $table, $query ) = @_;

    my $version = get_dump_version( $db );

    die( "table '$table' must end in 'dump'" ) if ( $table !~ /dump$/ );

    print STDERR "writing ${ table }_${ version } ...\n";

    eval { $db->query( "create temporary table ${ table }_${ version } as $query" ) };

    croak( $@ ) if ( $@ );
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
    my ( $db, $controversy ) = @_;

    my $tagset_name = "controversy_$controversy->{ name }";

    my $tags = $db->query(
        "select * from tags t, tag_sets ts " . "  where t.tag_sets_id = ts.tag_sets_id and ts.name = ? and t.tag <> 'all'",
        $tagset_name )->hashes;

    map { $_media_static_gexf_attribute_types->{ "tagged_" . $_->{ tag } } = 'integer' } @{ $tags };
}

sub add_codes_to_gexf_attribute_types
{
    my ( $db, $controversy ) = @_;

    my $code_types = $db->query( "select distinct code_type from controversy_media_codes where controversies_id = ?",
        $controversy->{ controversies_id } )->flat;

    map { $_media_static_gexf_attribute_types->{ "code_" . $_ } = 'string' } @{ $code_types };
}

sub get_link_weighted_edges
{
    my ( $db ) = @_;

    my $dump_version = get_dump_version( $db );

    my $media_links = $db->query( "select * from controversy_media_links_dump_${ dump_version }" )->hashes;

    my $edges = [];
    my $k     = 0;
    for my $media_link ( @{ $media_links } )
    {
        my $edge = {
            id     => $k++,
            source => $media_link->{ source_media_id },
            target => $media_link->{ ref_media_id },
            weight => $media_link->{ link_count }
        };

        push( @{ $edges }, $edge );
    }

    return $edges;
}

sub get_weighted_edges
{
    my ( $db, $weighting ) = @_;

    if ( $weighting eq 'link' )
    {
        return get_link_weighted_edges( $db );
    }
    else
    {
        die( "Unknown weighting '$weighting'" );
    }
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
    my ( $db, $controversy, $media_type ) = @_;

    $media_type ||= 'none';

    return $_media_type_color_map->{ $media_type } if ( $_media_type_color_map );

    my $all_media_types = $db->query(
        "select distinct code from controversy_media_codes where controversies_id = ? and code_type = 'media_type'",
        $controversy->{ controversies_id } )->flat;

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

# scale the size of the map described in the gexf file to 800 x 700.
# gephi can return really large maps that make the absolute node size relatively tiny.
# we need to scale the map to get consistent, reasonable node sizes across all maps
sub scale_map_size
{
    my ( $gexf_file ) = @_;

    my $gexf = XML::Simple::XMLin( $gexf_file, ForceArray => 1, ForceContent => 1, KeyAttr => [] );

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

    open( FILE, ">$gexf_file" ) || die( "Unable to open file '$gexf_file': $!" );

    print FILE encode( 'utf8', XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' ) );

    close FILE;

}

# call java program to lay out graph.  the java program accepts a gexf file as input and
# outputs a gexf file with the lay out included
sub write_layout_dump
{
    my ( $controversy, $dump_name ) = @_;

    print STDERR "generating gephi layout ...\n";

    my $nolayout_dump_path = get_dump_file_path( $controversy, "${ dump_name }_nolayout",     "gexf" );
    my $layout_dump_path   = get_dump_file_path( $controversy, "${ dump_name }_gephi_layout", "gexf" );

    my $cmd =
"java -cp $FindBin::Bin/../java/build/jar/GephiLayout.jar:FindBin::Bin/../java/lib/gephi-toolkit.jar edu.law.harvard.cyber.mediacloud.layout.GephiLayout '$nolayout_dump_path' '$layout_dump_path'";

    # print STDERR "$cmd\n";
    system( $cmd );

    scale_map_size( $layout_dump_path );

    return $layout_dump_path;
}

# get the size of the individual node based on the medium and the total number of links in the graph
sub get_node_size
{
    my ( $medium, $total_link_count ) = @_;

    print STDERR "get_node_size: $medium->{ name } [ $medium->{ link_count } / $total_link_count ]\n";

    my $scale = 100;

    # my $min_size = $scale * ( 1 / $total_link_count );
    # $scale = 3 * ( $scale / $min_size ) if ( $min_size < 3 );

    my $size = $scale * ( ( $medium->{ link_count } + 1 ) / $total_link_count );

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
    my ( $db, $controversy, $start_date, $end_date, $weighting ) = @_;

    my $dump_version = get_dump_version( $db );

    add_tags_to_gexf_attribute_types( $db, $controversy );
    add_codes_to_gexf_attribute_types( $db, $controversy );

    my $media   = $_dump_media;
    my $stories = $db->query(
        "select ssd.media_id, min( ssd.publish_date ) publish_date from controversy_stories_dump_${ dump_version } ssd " .
"  group by media_id, date_trunc( 'day', ssd.publish_date ) order by media_id, date_trunc( 'day', ssd.publish_date )"
    )->hashes;

    attach_stories_to_media( $stories, $media );

    my $gexf = {
        'xmlns'              => "http://www.gexf.net/1.2draft",
        'xmlns:xsi'          => "http://www.w3.org/2001/XMLSchema-instance",
        'xmlns:viz'          => "http://www.gexf.net/1.1draft/viz",
        'xsi:schemaLocation' => "http://www.gexf.net/1.2draft http://www.gexf.net/1.2draft/gexf.xsd",
        'version'            => "1.2"
    };

    my $meta = { 'lastmodifieddate' => Date::Format::time2str( '%Y-%m-%d', time ) };
    push( @{ $gexf->{ meta } }, $meta );

    push( @{ $meta->{ creator } },     'Berkman Center' );
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

    my $edges = get_weighted_edges( $db, $weighting );
    $graph->{ edges }->{ edge } = $edges;

    my $edge_lookup = {};
    for my $edge ( @{ $edges } )
    {
        $edge_lookup->{ $edge->{ source } } ||= 0;
        $edge_lookup->{ $edge->{ target } } += $edge->{ weight };
    }

    my $total_link_count = 1;
    map { $total_link_count += $_->{ link_count } } @{ $media };

    for my $medium ( @{ $media } )
    {
        my $node = {
            id    => $medium->{ media_id },
            label => $medium->{ name },
        };

        my $j = 0;
        while ( my ( $name, $type ) = each( %{ $_media_static_gexf_attribute_types } ) )
        {
            push( @{ $node->{ attvalues }->{ attvalue } }, { for => $j++, value => $medium->{ $name } } );
        }

        for my $story ( @{ $medium->{ stories } } )
        {
            my $story_date = substr( $story->{ publish_date }, 0, 10 );
            push( @{ $node->{ spells }->{ spell } }, { start => $story_date, end => $story_date } );
        }

        $node->{ 'viz:color' } = [ get_media_type_color( $db, $controversy, $medium->{ code_media_type } ) ];
        $node->{ 'viz:size' } = { value => $medium->{ link_count } + 1 };

        push( @{ $graph->{ nodes }->{ node } }, $node );
    }

    scale_node_sizes( $graph->{ nodes }->{ node } );

    my $xml_dump = XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' );

    my $dump_name = "controversy_media_${ weighting }";
    write_dump_file( $controversy, "${ dump_name }_nolayout", 'gexf', encode( 'utf8', $xml_dump ) );

    my $layout_dump_path = write_layout_dump( $controversy, $dump_name );

    return $layout_dump_path;
}

# add layout dump paths to the global list
sub add_layout_dump_path
{
    push( @{ $_layout_dump_paths }, @_ );
}

sub get_layout_dump_paths
{
    return $_layout_dump_paths;
}

# write an html file that has one link for each dump
sub write_layout_dump_links
{
    my $html = <<END;
<html>
<head>
<title>Layout Dump Paths</title>
</head>
<body>
<h1>Layout Dump Paths</h1>

<ul>
END

    my $layout_dump_paths = get_layout_dump_paths();
    for my $layout_dump_path ( @{ $layout_dump_paths } )
    {
        $html .= "<li><a href='http://cyber.law.harvard.edu/~hroberts/gexf/#$layout_dump_path'>$layout_dump_path</a></li>\n";
    }

    $html .= <<END;
</ul>
</body>
</html>
END

    my $parent_dump_dir = get_parent_dump_dir();

    my $layout_html = "$parent_dump_dir/layouts.html";

    open( FILE, ">$layout_html" ) || die( "Unable to open file '$layout_html': $!" );

    print FILE $html;

    close( FILE );
}

# return true if there are any stories in the current controversy_stories_dump_ table
sub stories_exist_for_period
{
    my ( $db, $controversy ) = @_;

    my $dump_version = get_dump_version( $db );

    return $db->query( "select 1 from controversy_stories_dump_${ dump_version }" )->hash;
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

# generate the dumps for the given period, dates, and weightings
sub generate_period_dump
{
    my ( $db, $controversies_id, $start_date, $end_date, $period, $weightings ) = @_;

    my $dump_label = "${ period }_${ start_date }_${ end_date }";
    set_dump_label( $dump_label );

    print "generating $dump_label...\n";

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "Unable to find controversy '$controversies_id'" );

    write_link_counts( $db, $controversy, $start_date, $end_date );

    write_controversy_links_dump( $db, $controversy, $start_date, $end_date );

    write_controversy_stories_dump( $db, $controversy, $start_date, $end_date );

    if ( !stories_exist_for_period( $db, $controversy ) )
    {
        print STDERR "skipping $dump_label because no stories exist\n";
        return;
    }

    write_controversy_media_dump( $db, $controversy );

    write_controversy_media_links_dump( $db, $controversy );

    write_controversy_date_counts_dump( $db, $controversy, $start_date, $end_date, 'day' );

    write_controversy_date_counts_dump( $db, $controversy, $start_date, $end_date, 'week' );

    map { add_layout_dump_path( write_gexf_dump( $db, $controversy, $start_date, $end_date, $_ ) ) } @{ $weightings };

}

# decrease the given date to the latest monday equal to or before the date
sub truncate_to_monday
{
    my ( $date ) = @_;

    my $epoch_date = MediaWords::Util::SQL::get_epoch_from_sql_date( $date );
    my $week_day   = ( localtime( $epoch_date ) )[ 6 ];

    # mod this to account for sunday, for which $week_day - 1 == -1
    my $days_offset = ( $week_day - 1 ) % 7;

    return MediaWords::Util::SQL::increment_day( $date, -1 * $days_offset );
}

# decrease the given date to the first day of the current month
sub truncate_to_start_of_month
{
    my ( $date ) = @_;

    my $epoch_date = MediaWords::Util::SQL::get_epoch_from_sql_date( $date );
    my $month_day  = ( localtime( $epoch_date ) )[ 3 ];

    my $days_offset = $month_day - 1;

    return MediaWords::Util::SQL::increment_day( $date, -1 * $days_offset );
}

# generate dumps for the periods in controversy_dates
sub generate_custom_period_dumps
{
    my ( $db, $controversies_id, $weightings ) = @_;

    my $controversy_dates = $db->query( <<END, $controversies_id )->hashes;
select * from controversy_dates where controversies_id = ? order by start_date, end_date
END

    for my $controversy_date ( @{ $controversy_dates } )
    {
        my $start_date = $controversy_date->{ start_date };
        my $end_date   = $controversy_date->{ end_date };
        generate_period_dump( $db, $controversies_id, $start_date, $end_date, 'custom', $weightings );
    }
}

# generate dumps for the given period (overall, monthly, weekly, or custom)
sub generate_all_period_dumps
{
    my ( $db, $controversies_id, $start_date, $end_date, $period, $weightings ) = @_;

    if ( $period eq 'overall' )
    {
        generate_period_dump( $db, $controversies_id, $start_date, $end_date, $period, $weightings );
    }
    elsif ( $period eq 'weekly' )
    {
        my $w_start_date = truncate_to_monday( $start_date );
        while ( $w_start_date lt $end_date )
        {
            my $w_end_date = MediaWords::Util::SQL::increment_day( $w_start_date, 7 );

            generate_period_dump( $db, $controversies_id, $w_start_date, $w_end_date, $period, $weightings );

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

            generate_period_dump( $db, $controversies_id, $m_start_date, $m_end_date, $period, $weightings );

            $m_start_date = $m_end_date;
        }
    }
    elsif ( $period eq 'custom' )
    {
        generate_custom_period_dumps( $db, $controversies_id, $weightings );
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

sub main
{
    my ( $start_date, $end_date, $period, $weighting, $controversies_id, $cleanup_data );

    $period    = 'all';
    $weighting = 'link';

    Getopt::Long::GetOptions(
        "start_date=s"  => \$start_date,
        "end_date=s"    => \$end_date,
        "period=s"      => \$period,
        "controversy=s" => \$controversies_id,
        "cleanup_data!" => \$cleanup_data
    ) || return;

    $weighting = 'link';

    die(
"Usage: $0 --controversy < id > [ --start_date < start date > --end_date < end date > --period < overall|weekly|monthly|all|custom > --cleanup_data ]"
    ) unless ( $controversies_id );

    my $all_periods    = [ qw(custom overall weekly monthly) ];
    my $all_weightings = [ qw(link text text+link) ];

    die( "period must be all, custom, overall, weekly, or monthly" )
      if ( $period && !grep { $_ eq $period } ( 'all', @{ $all_periods } ) );

    die( "weighting must be all, link, text, or text+link" )
      if ( !grep { $_ eq $weighting } ( 'all', @{ $all_weightings } ) );

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "Unable to find controversy '$controversies_id'" );

    if ( !$start_date || !$end_date )
    {
        my ( $default_start_date, $default_end_date ) = get_default_dates( $db, $controversy );
        $start_date ||= $default_start_date;
        $end_date   ||= $default_end_date;
    }

    my $periods = ( $period eq 'all' ) ? $all_periods : [ $period ];

    for my $p ( @{ $periods } )
    {
        my $weightings = ( $weighting eq 'all' ) ? $all_weightings : [ $weighting ];
        generate_all_period_dumps( $db, $controversies_id, $start_date, $end_date, $p, $weightings );
    }

    write_layout_dump_links();

    write_cleanup_dumps( $db, $controversy ) if ( $cleanup_data );
}

main();

__END__
