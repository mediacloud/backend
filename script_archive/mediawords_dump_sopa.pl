#!/usr/bin/env perl

# dump various sopa queries to csv

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Color::Mix;
use Date::Format;
use Encode;
use File::Path;
use Getopt::Long;
use XML::Simple;

use MediaWords::DB;
use MediaWords::Util::CSV;
use MediaWords::Util::Colors;
use MediaWords::Util::SQL;

my $_num_similar_stories_per_story = 10;

my $_media_type_color_map;

my $_dump_version;
my $_dump_label;

my $_media_static_gexf_attribute_types = {
    url                 => 'string',
    media_type          => 'string',
    link_weight         => 'float',
    link_count          => 'integer',
    story_count         => 'integer',
    sentiment_58billion => 'integer',
};

sub set_dump_label
{
    ( $_dump_label ) = @_;
}

sub get_dump_label
{
    return $_dump_label;
}

# append the dump label to the dump file name, add the extension, and write to the dump dir
sub write_dump_file
{
    my ( $file_name, $extension, $encoded_data ) = @_;

    my $dump_label = get_dump_label();

    my $parent_dump_dir = "sopa_dumps/sopa_dumps_" . Date::Format::time2str( '%Y-%m-%d', time );
    File::Path::mkpath( $parent_dump_dir ) unless ( -d $parent_dump_dir );

    my $dump_dir = "$parent_dump_dir/sopa_dump_${ dump_label }";
    mkdir( $dump_dir ) unless ( -d $dump_dir );

    open( FILE, ">$dump_dir/${ file_name }_${ dump_label }.${ extension }" ) || die( "Unable to open dump file: $!" );

    print FILE $encoded_data;

    close( FILE );

}

# write the results of the query as a csv
sub write_dump_as_csv
{
    my ( $db, $table, $query ) = @_;

    replace_table_contents( $db, $table, $query );

    my $dump_version = get_dump_version( $db );

    my $res = $db->query( "select * from ${ table }_${ dump_version }" );

    my $fields = $res->columns;

    my $data = $res->hashes;

    my $csv_string = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $data, $fields );

    write_dump_file( $table, 'csv', $csv_string );
}

sub write_story_text_links
{
    my ( $db, $start_date, $end_date ) = @_;

    my $sopa_links_sub_query = <<END;
    select distinct stories_id from 
            ( ( select distinct sl.stories_id from sopa_links_cross_media sl, stories s, stories r 
                    where sl.stories_id = s.stories_id and r.stories_id = sl.ref_stories_id and 
                        s.publish_date between '$start_date' and '$end_date'::timestamp - interval '1 second' and 
                        s.publish_date > r.publish_date - interval '1 day' ) union
              ( select distinct sl.ref_stories_id from sopa_links_cross_media sl, stories s, stories r 
                    where sl.ref_stories_id = r.stories_id and sl.stories_id = s.stories_id and 
                        r.publish_date between '$start_date' and '$end_date'::timestamp - interval '1 second' and 
                        s.publish_date > r.publish_date - interval '1 day' ) ) slsq
END

    write_dump_as_csv( $db, 'sopa_story_text_links_dump', <<END );
select * from (
    select stories_id_a, publish_day_a, stories_id_b, publish_day_b, similarity, 
        rank() over ( partition by stories_id_a order by similarity desc ) as similarity_rank
      from story_similarities_transitive sst, stories s_a, stories s_b,
        ( $sopa_links_sub_query ) sl_a,
        ( $sopa_links_sub_query ) sl_b
      where sst.stories_id_a = s_a.stories_id and sst.stories_id_b = s_b.stories_id and 
        s_a.media_id <> s_b.media_id and 
        s_a.stories_id = sl_a.stories_id and s_b.stories_id = sl_b.stories_id
  ) q
  where similarity_rank <=  $_num_similar_stories_per_story
END
}

sub write_media_text_links
{
    my ( $db, $start_date, $end_date ) = @_;

    my $dump_version = get_dump_version( $db );

    write_dump_as_csv( $db, 'sopa_media_text_links_dump',
        "select sum( similarity ) similarity_sum, count(*) similarity_count, " .
          "    m_a.media_id media_id_a, min( m_a.name ) media_name_a, min( m_a.url ) media_url_a, " .
          "    m_b.media_id media_id_b, min( m_b.name ) media_name_b, min( m_b.url ) media_url_b " .
          "  from sopa_story_text_links_dump_${ dump_version } sstld, stories s_a, stories s_b, media m_a, media m_b " .
          "  where sstld.stories_id_a = s_a.stories_id and sstld.stories_id_b = s_b.stories_id and " .
          "    s_a.media_id = m_a.media_id and s_b.media_id = m_b.media_id " . "  group by m_a.media_id, m_b.media_id " );
}

sub write_link_counts
{
    my ( $db, $start_date, $end_date ) = @_;

    replace_table_contents( $db, 'sopa_story_link_counts_dump',
        "select count(*) link_count, ref_stories_id " . "  from sopa_links_cross_media sl, stories s, stories r " .
          "  where sl.stories_id = s.stories_id and sl.ref_stories_id = r.stories_id and " .
          "    ( s.publish_date between '$start_date' and '$end_date'::timestamp - interval '1 second' ) and " .
          "    s.publish_date > r.publish_date - interval '1 day'" . "  group by ref_stories_id" );

    replace_table_contents( $db, 'sopa_story_outlink_counts_dump',
        "select count(*) outlink_count, sl.stories_id " . "  from sopa_links_cross_media sl, stories s, stories r " .
          "  where sl.stories_id = s.stories_id and sl.ref_stories_id = r.stories_id and " .
          "    ( s.publish_date between '$start_date' and '$end_date'::timestamp - interval '1 second' ) and " .
          "    s.publish_date > r.publish_date - interval '1 day'" . "  group by sl.stories_id" );

    replace_table_contents( $db, 'sopa_story_outlink_counts_dump',
        "select count(*) outlink_count, sl.stories_id " . "  from sopa_links_cross_media sl, stories s, stories r " .
          "  where sl.stories_id = s.stories_id and sl.ref_stories_id = r.stories_id and " .
          "    ( s.publish_date between '$start_date' and '$end_date'::timestamp - interval '1 second' ) " .
          "  group by sl.stories_id" );

}

sub write_sopa_stories_dump
{
    my ( $db, $start_date, $end_date ) = @_;

    my $tags = $db->query( "select * from tags t, tag_sets ts " .
          "  where t.tag_sets_id = ts.tag_sets_id and ts.name = 'sopa' and t.tag <> 'all'" )->hashes;

    my $tag_clauses = [];
    for my $tag ( @{ $tags } )
    {
        my $label = "tagged_" . lc( $tag->{ tag } );
        $label =~ s/[^[[:alnum:]]]/_/g;

        push(
            @{ $tag_clauses },
            "exists ( select 1 from stories_tags_map stm " .
              "  where s.stories_id = stm.stories_id and stm.tags_id = $tag->{ tags_id } ) $label "
        );
    }

    my $tag_clause_list = join( ',', @{ $tag_clauses } );

    my $dump_version = get_dump_version( $db );

    write_dump_as_csv( $db, 'sopa_stories_dump', <<END );
select distinct s.stories_id, s.title, s.url, s.publish_date, 
        m.name media_name, m.url media_url, m.media_id, ss.link_weight, 
        coalesce( lc.link_count, 0) link_count,  coalesce( olc.outlink_count, 0) outlink_count, 
        coalesce( lc.link_count, 0) + coalesce( olc.outlink_count, 0) total_link_count, $tag_clause_list
	from stories s, media m, sopa_stories ss  
	    left join sopa_story_link_counts_dump_${ dump_version } as lc on ( ss.stories_id = lc.ref_stories_id )
	    left join sopa_story_outlink_counts_dump_${ dump_version } as olc on ( ss.stories_id = olc.stories_id )
	where ss.stories_id = s.stories_id and s.media_id = m.media_id and
        ( s.stories_id in ( 
            ( select sl.source_stories_id from sopa_links_dump_${ dump_version } sl ) union
            ( select sl.ref_stories_id from sopa_links_dump_${ dump_version } sl ) ) 
          or s.publish_date between '$start_date' and '$end_date'::timestamp - interval '1 second' )
	order by s.publish_date;
END
}

sub write_sopa_links_dump
{
    my ( $db, $start_date, $end_date ) = @_;

    write_dump_as_csv( $db, 'sopa_links_dump', <<END );
select distinct sl.stories_id source_stories_id, ss.title source_title, ss.url source_url, 
        sm.name source_media_name, sm.url source_media_url, sm.media_id source_media_id,
		sl.ref_stories_id ref_stories_id, rs.title ref_title, rs.url ref_url, rm.name ref_media_name, rm.url ref_media_url, 
		rm.media_id ref_media_id
	from sopa_links_cross_media sl, stories ss, media sm, stories rs, media rm
	where sl.stories_id = ss.stories_id and ss.media_id = sm.media_id and sl.ref_stories_id = rs.stories_id and rs.media_id = rm.media_id
	  and ( ss.publish_date between '$start_date' and '$end_date'::timestamp - interval '1 second' ) and
      ss.publish_date > rs.publish_date - interval '1 day'
END
}

sub write_sopa_media_dump
{
    my ( $db ) = @_;

    my $tags = $db->query( "select * from tags t, tag_sets ts " .
          "  where t.tag_sets_id = ts.tag_sets_id and ts.name = 'sopa' and t.tag <> 'all'" )->hashes;

    my $tag_fields = [];
    for my $tag ( @{ $tags } )
    {
        my $label = "tagged_" . lc( $tag->{ tag } );
        $label =~ s/[^[[:alnum:]]]/_/g;

        push( @{ $tag_fields }, "bool_or( $label ) $label" );
    }

    my $tag_fields_list = join( ',', @{ $tag_fields } );

    my $dump_version = get_dump_version( $db );

    write_dump_as_csv( $db, 'sopa_media_dump', <<END );
select m.media_id, m.name, m.url, min( ssd.publish_date ) start_date, max( ssd.publish_date ) end_date,
        sum( ssd.link_count) link_count, sum( ssd.outlink_count) outlink_count,
        sum( ssd.total_link_count ) total_link_count, sum( ssd.link_weight ) link_weight, 
        count(*) story_count, min( smt.media_type) media_type, ${ tag_fields_list },
        coalesce( min( sm5m.sentiment ), 0 ) sentiment_58billion
  from media m left join sopa_media_types smt on ( m.media_id = smt.media_id )
      join sopa_stories_dump_${ dump_version } ssd on ( ssd.media_id = m.media_id )
      left join sopa_media_58b_sentiment sm5m on ( m.media_id = sm5m.media_id )
  group by m.media_id, m.name, m.url
  order by sum( ssd.link_weight );    
END
}

sub write_sopa_media_links_dump
{
    my ( $db ) = @_;

    my $dump_version = get_dump_version( $db );

    write_dump_as_csv( $db, 'sopa_media_links_dump', <<END );
select source_media_id, ref_media_id, count(*) link_count
  from sopa_links_dump_${ dump_version } group by source_media_id, ref_media_id
END
}

sub write_sopa_date_counts_dump
{
    my ( $db, $start_date, $end_date ) = @_;

    my $tags =
      $db->query( "select * from tags t, tag_sets ts " . "  where t.tag_sets_id = ts.tag_sets_id and ts.name = 'sopa'" )
      ->hashes;

    my $tag_fields  = [];
    my $tag_queries = [];
    for my $tag ( @{ $tags } )
    {
        my $label = "count_" . lc( $tag->{ tag } );
        $label =~ s/[^[[:alnum:]]]/_/g;

        push( @{ $tag_fields }, "coalesce( $label.week_count, 0 ) week_$label" );

        push(
            @{ $tag_queries },
            "left join ( select count(*) week_count,  date_trunc( 'week', a.publish_date ) publish_week " .
              "      from stories_tags_map stm, stories a " .
              "      where a.stories_id = stm.stories_id and stm.tags_id = $tag->{ tags_id } " .
              "      group by date_trunc( 'week', a.publish_date ) ) " .
              "  as $label on ( all_weeks.publish_week = $label.publish_week )"
        );
    }

    my $tag_fields_list  = join( ', ', @{ $tag_fields } );
    my $tag_queries_list = join( ' ',  @{ $tag_queries } );

    write_dump_as_csv( $db, 'sopa_date_counts_dump', <<END );
select all_weeks.publish_week, $tag_fields_list
    from ( select distinct date_trunc( 'week', s.publish_date ) publish_week
             from stories s join sopa_stories ss on ( s.stories_id = ss.stories_id ) ) all_weeks
         $tag_queries_list
         where all_weeks.publish_week between '$start_date' and '$end_date'::timestamp - interval '1 second'
         order by all_weeks.publish_week
END
}

sub get_dump_version
{
    my ( $db ) = @_;

    return $_dump_version if ( $_dump_version );

    my $last_media_dump = $db->query(
"select tablename from pg_tables where tablename like 'sopa_story_link_counts_dump_%' order by tablename desc limit 1"
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

    die( "table must end in 'dump'" ) if ( $table !~ /dump$/ );

    print STDERR "writing ${ table }_${ version } ...\n";

    $db->query( "create temporary table ${ table }_${ version } as $query" );
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
    my ( $db ) = @_;

    my $tags = $db->query( "select * from tags t, tag_sets ts " .
          "  where t.tag_sets_id = ts.tag_sets_id and ts.name = 'sopa' and t.tag <> 'all'" )->hashes;

    map { $_media_static_gexf_attribute_types->{ "tagged_" . $_->{ tag } } = 'integer' } @{ $tags };
}

sub get_link_weighted_edges
{
    my ( $db ) = @_;

    my $dump_version = get_dump_version( $db );

    my $media_links = $db->query( "select * from sopa_media_links_dump_${ dump_version }" )->hashes;

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

sub get_text_weighted_edges
{
    my ( $db, $k ) = @_;

    my $dump_version = get_dump_version( $db );

    my $media_text_links = $db->query( "select * from sopa_media_text_links_dump_${ dump_version }" )->hashes;

    my $edges      = [];
    my $k          = 0;
    my $max_weight = 0;
    for my $media_text_link ( @{ $media_text_links } )
    {
        my $edge = {
            id     => $k++,
            source => $media_text_link->{ media_id_a },
            target => $media_text_link->{ media_id_b },
            weight => $media_text_link->{ similarity_sum }
        };

        $max_weight = ( $max_weight < $edge->{ weight } ) ? $edge->{ weight } : $max_weight;

        push( @{ $edges }, $edge );
    }

    $max_weight /= 10;
    map { $_->{ weight } /= $max_weight } @{ $edges };

    return $edges;
}

sub get_textlink_weighted_edges
{
    my ( $db ) = @_;

    my $dump_version = get_dump_version( $db );

    my ( $media_links_sum ) = $db->query( "select sum( link_count ) from sopa_media_links_dump_${ dump_version } " )->flat;
    my ( $media_text_links_sum ) =
      $db->query( "select sum( similarity_sum ) from sopa_media_text_links_dump_${ dump_version } " )->flat;

    return get_text_weighted_edges( $db ) unless ( $media_links_sum );

    my $scaling_factor = $media_text_links_sum / $media_links_sum;

    my $link_edges = get_link_weighted_edges( $db );
    my $text_edges = get_text_weighted_edges( $db );

    my $link_edges_map = {};
    map { $link_edges_map->{ $_->{ source } }->{ $_->{ target } } = $_ } @{ $link_edges };

    for my $text_edge ( @{ $text_edges } )
    {
        $text_edge->{ weight } /= $scaling_factor;
        if ( my $link_edge = $link_edges_map->{ $text_edge->{ source } }->{ $text_edge->{ target } } )
        {
            $link_edge->{ weight } += $text_edge->{ weight };
        }
        else
        {
            $text_edge->{ id } = scalar( @{ $link_edges } );
            push( @{ $link_edges }, $text_edge );
        }
    }

    return $link_edges;
}

sub get_weighted_edges
{
    my ( $db, $weighting ) = @_;

    if ( $weighting eq 'link' )
    {
        return get_link_weighted_edges( $db );
    }
    elsif ( $weighting eq 'text' )
    {
        return get_text_weighted_edges( $db );
    }
    elsif ( $weighting eq 'text+link' )
    {
        return get_textlink_weighted_edges( $db );
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
    my ( $db, $media_type ) = @_;

    $media_type ||= 'none';

    return $_media_type_color_map->{ $media_type } if ( $_media_type_color_map );

    my $all_media_types = $db->query( "select distinct media_type from sopa_media_types order by media_type" )->hashes;

    my $num_colors = scalar( @{ $all_media_types } ) + 1;

   # my $color_mix = Color::Mix->new;
   # my $color_list = [ map { get_color_hash_from_hex( $_ ) } $color_mix->analogous( '0000ff',  $num_colors, $num_colors ) ];
    my $color_list = MediaWords::Util::Colors::get_colors( $num_colors, 'rgb()' );

    $_media_type_color_map = {};
    for my $media_type ( @{ $all_media_types } )
    {
        $_media_type_color_map->{ $media_type->{ media_type } } = pop( @{ $color_list } );
    }

    $_media_type_color_map->{ none } = pop( @{ $color_list } );

    return $_media_type_color_map->{ $media_type };
}

# <node id="1"  label=" ">
#            <attvalues>
#              <attvalue for="Objet" value="Tree"></attvalue>
#              <attvalue for="ObjectSize" value="10"></attvalue>
#            </attvalues>
#            <viz:size value="110.1"></viz:size>
#            <viz:position x="-1865.1819" y="227.53818"></viz:position>
#            <viz:color r="124" g="189" b="113"></viz:color>
#          </node>
sub write_gexf_dump
{
    my ( $db, $start_date, $end_date, $weighting ) = @_;

    my $dump_version = get_dump_version( $db );

    add_tags_to_gexf_attribute_types( $db );

    my $media = $db->query( "select smd.* from sopa_media_dump_${ dump_version } smd order by link_count desc" )->hashes;
    my $stories =
      $db->query( "select ssd.media_id, min( ssd.publish_date ) publish_date from sopa_stories_dump_${ dump_version } ssd " .
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
    push( @{ $meta->{ description } }, 'Media discussions of SOPA' );

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

    for my $medium ( @{ $media } )
    {

        # only use media sources that are at the end of some edge
        next unless ( defined( $edge_lookup->{ $medium->{ media_id } } ) );

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

        $node->{ 'viz:color' } = [ get_media_type_color( $db, $medium->{ media_type } ) ];

        push( @{ $graph->{ nodes }->{ node } }, $node );
    }

    my $xml_dump = XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' );

    write_dump_file( "sopa_media_${ weighting }", 'gexf', encode( 'utf8', $xml_dump ) );
}

sub generate_period_dump
{
    my ( $start_date, $end_date, $period, $weightings ) = @_;

    my $dump_label = "${ period }_${ start_date }_${ end_date }";
    set_dump_label( $dump_label );

    print "generating $dump_label...\n";

    my $db = MediaWords::DB::connect_to_db;

    # write_story_text_links( $db, $start_date, $end_date );
    #
    # write_media_text_links( $db, $start_date, $end_date );
    #
    write_link_counts( $db, $start_date, $end_date );

    write_sopa_links_dump( $db, $start_date, $end_date );

    write_sopa_stories_dump( $db, $start_date, $end_date );

    write_sopa_media_dump( $db );

    write_sopa_media_links_dump( $db );

    write_sopa_date_counts_dump( $db, $start_date, $end_date );

    map { write_gexf_dump( $db, $start_date, $end_date, $_ ) } @{ $weightings };
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

sub generate_all_period_dumps
{
    my ( $start_date, $end_date, $period, $weightings ) = @_;

    if ( $period eq 'overall' )
    {
        generate_period_dump( $start_date, $end_date, $period, $weightings );
    }
    elsif ( $period eq 'weekly' )
    {
        my $w_start_date = truncate_to_monday( $start_date );
        while ( $w_start_date lt $end_date )
        {
            my $w_end_date = MediaWords::Util::SQL::increment_day( $w_start_date, 7 );

            generate_period_dump( $w_start_date, $w_end_date, $period, $weightings );

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

            generate_period_dump( $m_start_date, $m_end_date, $period, $weightings );

            $m_start_date = $m_end_date;
        }
    }
    else
    {
        die( "Unknown period '$period'" );
    }
}

sub main
{
    my ( $start_date, $end_date, $period, $weighting );

    $period = 'all';

    Getopt::Long::GetOptions(
        "start_date=s" => \$start_date,
        "end_date=s"   => \$end_date,
        "period=s"     => \$period,
        "weighting=s"  => \$weighting
    ) || return;

    die(
"Usage: $0 --start_date < start date > --end_date < end date > --period < overall|weekly|monthly|all > --weighting < link|text|text+link >"
    ) unless ( $start_date && $end_date && $period && $weighting );

    my $all_periods    = [ qw(overall weekly monthly) ];
    my $all_weightings = [ qw(link text text+link) ];

    die( "period must be all, overall, weekly, or monthly" )
      if ( $period && !grep { $_ eq $period } ( 'all', @{ $all_periods } ) );

    die( "weighting must be all, link, text, or text+link" )
      if ( !grep { $_ eq $weighting } ( 'all', @{ $all_weightings } ) );

    my $periods = ( $period eq 'all' ) ? $all_periods : [ $period ];

    for my $p ( @{ $periods } )
    {
        my $weightings = ( $weighting eq 'all' ) ? $all_weightings : [ $weighting ];
        generate_all_period_dumps( $start_date, $end_date, $p, $weightings );
    }
}

main();

__END__
