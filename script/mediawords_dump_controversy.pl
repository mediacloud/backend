#!/usr/bin/env perl

# dump various controversy queries to csv and build a gexf file

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
use MediaWords::Util::SQL;

my $_num_similar_stories_per_story = 10;

my $_media_type_color_map;

my $_dump_version;
my $_dump_label;

my $_media_static_gexf_attribute_types = {
    url => 'string',
    media_type => 'string',
    link_weight => 'float', 
    link_count => 'integer',
    story_count => 'integer',
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
    my ( $controversy, $file_name, $extension, $encoded_data ) = @_;
    
    my $dump_label = get_dump_label();
    
    my $controversy_name = $controversy->{ name };
    $controversy_name =~ s/\//_/g;
    
    my $parent_dump_dir = "controversy_dumps/$controversy_name";
    File::Path::mkpath( $parent_dump_dir ) unless ( -d $parent_dump_dir );
    
    my $dump_dir = "$parent_dump_dir/controversy_dump_${ dump_label }";    
    mkdir( $dump_dir ) unless ( -d $dump_dir );
    
    open( FILE, ">$dump_dir/${ file_name }_${ dump_label }.${ extension }" ) || die( "Unable to open dump file: $!" );
    
    print FILE $encoded_data;
    
    close( FILE );

}

# write the results of the query as a csv
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
        "select count(*) link_count, ref_stories_id " . 
        "  from controversy_links_cross_media cl, stories s, stories r " . 
        "  where cl.stories_id = s.stories_id and cl.ref_stories_id = r.stories_id and " .
        "    ( s.publish_date between '$start_date' and '$end_date'::timestamp - interval '1 second' ) and " .
        "    controversies_id = $controversy->{ controversies_id } " .
        "  group by ref_stories_id" );

    replace_table_contents( $db, 'controversy_story_outlink_counts_dump', 
        "select count(*) outlink_count, cl.stories_id " . 
        "  from controversy_links_cross_media cl, stories s, stories r " . 
        "  where cl.stories_id = s.stories_id and cl.ref_stories_id = r.stories_id and " .
        "    ( s.publish_date between '$start_date' and '$end_date'::timestamp - interval '1 second' ) and " .
        "    cl.controversies_id = $controversy->{ controversies_id } " .
        "  group by cl.stories_id" );

}

sub write_controversy_stories_dump
{
    my ( $db, $controversy, $start_date, $end_date ) = @_;
    
    my $tagset_name = "Controversy $controversy->{ name }";

    my $tags = $db->query(
        "select * from tags t, tag_sets ts " .
        "  where t.tag_sets_id = ts.tag_sets_id and ts.name = ? and t.tag <> 'all'", $tagset_name )->hashes;
        
    my $tag_clauses = [];
    for my $tag ( @{ $tags } )
    {
        my $label = "tagged_" . lc( $tag->{ tag } );
        $label =~ s/[^[[:alnum:]]]/_/g;
        
        push( @{ $tag_clauses}, 
            "exists ( select 1 from stories_tags_map stm "  .
            "  where s.stories_id = stm.stories_id and stm.tags_id = $tag->{ tags_id } ) $label ");
    }
    
    my $tag_clause_list = join( ',', @{ $tag_clauses } );
    $tag_clause_list = ", $tag_clause_list" if ( $tag_clause_list );
    
    my $dump_version = get_dump_version( $db );
    
    my $cid = $controversy->{ controversies_id } ;
    
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
          or s.publish_date between '$start_date' and '$end_date'::timestamp - interval '1 second' )
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
	where cl.stories_id = ss.stories_id and ss.media_id = sm.media_id and cl.ref_stories_id = rs.stories_id and rs.media_id = rm.media_id
	  and ( ss.publish_date between '$start_date' and '$end_date'::timestamp - interval '1 second' ) and
	  cl.controversies_id = $controversy->{ controversies_id }
END
}

sub write_controversy_media_dump
{
    my ( $db, $controversy ) = @_;
    
    my $tagset_name = "Controversy $controversy->{ name }";
    
    my $tags = $db->query(
        "select * from tags t, tag_sets ts " .
        "  where t.tag_sets_id = ts.tag_sets_id and ts.name = ? and t.tag <> 'all'", $tagset_name )->hashes;
        
    my $tag_fields = [];
    for my $tag ( @{ $tags } )
    {
        my $label = "tagged_" . lc( $tag->{ tag } );
        $label =~ s/[^[[:alnum:]]]/_/g;
        
        push( @{ $tag_fields}, "bool_or( $label ) $label" );
    }
    
    my $tag_fields_list = join( ',', @{ $tag_fields } );
    
    my $dump_version = get_dump_version( $db );
    
    write_dump_as_csv( $db, $controversy, 'controversy_media_dump', <<END );
select m.media_id, m.name, m.url, min( ssd.publish_date ) start_date, max( ssd.publish_date ) end_date,
        sum( ssd.link_count) link_count, sum( ssd.outlink_count) outlink_count,
        sum( ssd.total_link_count ) total_link_count, sum( ssd.link_weight ) link_weight, 
        count(*) story_count, smt.media_type
  from media m join controversy_stories_dump_${ dump_version } ssd on ( ssd.media_id = m.media_id )
    left join sopa_media_types smt on ( m.media_id = smt.media_id )
  group by m.media_id, m.name, m.url, smt.media_type
  order by sum( ssd.link_weight );    
END
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

sub write_controversy_date_counts_dump
{
    my ( $db, $controversy, $start_date, $end_date ) = @_;
    
    my $tagset_name = "Controversy $controversy->{ name }";

    my $tags = $db->query(
        "select * from tags t, tag_sets ts "  .
        "  where t.tag_sets_id = ts.tag_sets_id and ts.name = ?", $tagset_name )->hashes;
        
    my $tag_fields = [];
    my $tag_queries = [];
    for my $tag ( @{ $tags } )
    {
        my $label = "count_" . lc( $tag->{ tag } );
        $label =~ s/[^[[:alnum:]]]/_/g;
        
        push( @{ $tag_fields }, "coalesce( $label.week_count, 0 ) week_$label" );
        
        push( @{ $tag_queries},
            "left join ( select count(*) week_count,  date_trunc( 'week', a.publish_date ) publish_week " . 
            "      from stories_tags_map stm, stories a " . 
            "      where a.stories_id = stm.stories_id and stm.tags_id = $tag->{ tags_id } " . 
            "      group by date_trunc( 'week', a.publish_date ) ) " . 
            "  as $label on ( all_weeks.publish_week = $label.publish_week )");
    }
    
    my $tag_fields_list = join( ', ', @{ $tag_fields } );
    my $tag_queries_list = join( ' ', @{ $tag_queries } );
    
    my $cid = $controversy->{ controversies_id };
    
    write_dump_as_csv( $db, $controversy, 'controversy_date_counts_dump', <<END );
select all_weeks.publish_week, $tag_fields_list
    from ( select distinct date_trunc( 'week', s.publish_date ) publish_week
             from stories s join controversy_stories cs on ( s.stories_id = cs.stories_id and controversies_id = $cid ) ) all_weeks
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
        "select tablename from pg_tables where tablename like 'controversy_story_link_counts_dump_%' order by tablename desc limit 1" )->hash;
        
    if ( $last_media_dump )
    {    
        $last_media_dump->{ tablename } =~ /(\d+)$/ || die( "Can't parse media dump table name: '$last_media_dump->{ tablename }'" );
        my $version = $1;
        
        $_dump_version = sprintf( "%06d", $version + 1 );
    }
    else {
        $_dump_version = sprintf( "%06d", 1 );
    } 
    
    return $_dump_version;   
}

sub replace_table_contents
{
    my ( $db, $table, $query ) = @_;
    
    my $version = get_dump_version( $db );
    
    die ( "table '$table' must end in 'dump'") if ( $table !~ /dump$/ );
    
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
    my ( $db, $controversy ) = @_;
        
    my $tagset_name = "Controversy $controversy->{ name }";

    my $tags = $db->query(
        "select * from tags t, tag_sets ts "  .
        "  where t.tag_sets_id = ts.tag_sets_id and ts.name = ? and t.tag <> 'all'", $tagset_name )->hashes;
        
    map { $_media_static_gexf_attribute_types->{ "tagged_" . $_->{ tag } } = 'integer' } @{ $tags };
}

sub get_link_weighted_edges
{
    my ( $db ) = @_;
    
    my $dump_version = get_dump_version( $db );
    
    my $media_links = $db->query( "select * from controversy_media_links_dump_${ dump_version }" )->hashes;

    my $edges = [];
    my $k = 0;
    for my $media_link ( @{ $media_links } )
    {
        my $edge = { 
            id => $k++, 
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
        b => hex( substr( $rgb_hex, 4, 2 ) ) };
}

sub get_media_type_color
{
    my ( $db, $media_type ) = @_;
        
    $media_type ||= 'none';
        
    return $_media_type_color_map->{ $media_type } if ( $_media_type_color_map );
    
    my $all_media_types = $db->query( "select distinct media_type from controversy_media_types order by media_type" )->hashes;
    
    my $num_colors = scalar( @{ $all_media_types } ) + 1;
    
    my $color_mix = Color::Mix->new;
    my $color_list = [ map { get_color_hash_from_hex( $_ ) } $color_mix->analogous( '0000ff',  $num_colors, $num_colors ) ];
    
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
    my ( $db, $controversy, $start_date, $end_date, $weighting ) = @_;
    
    my $dump_version = get_dump_version( $db );
    
    add_tags_to_gexf_attribute_types( $db, $controversy );
    
    my $media = $db->query( 
        "select smd.* from controversy_media_dump_${ dump_version } smd order by link_count desc" )->hashes;
    my $stories = $db->query( 
        "select ssd.media_id, min( ssd.publish_date ) publish_date from controversy_stories_dump_${ dump_version } ssd " . 
        "  group by media_id, date_trunc( 'day', ssd.publish_date ) order by media_id, date_trunc( 'day', ssd.publish_date )" )->hashes;
        
    attach_stories_to_media( $stories, $media );
    
    my $gexf = { 
        'xmlns'                 => "http://www.gexf.net/1.2draft",
        'xmlns:xsi'             => "http://www.w3.org/2001/XMLSchema-instance",
        'xmlns:viz'             => "http://www.gexf.net/1.1draft/viz",
        'xsi:schemaLocation'    => "http://www.gexf.net/1.2draft http://www.gexf.net/1.2draft/gexf.xsd",
        'version'               => "1.2"
    };
    
    my $meta = { 'lastmodifieddate' =>  Date::Format::time2str( '%Y-%m-%d', time ) };
    push( @{ $gexf->{ meta } }, $meta );
    
    push( @{ $meta->{ creator } }, 'Berkman Center' );
    push( @{ $meta->{ description } }, 'Media discussions of $controversy->{ name }' );
    
    my $graph = {
        'mode'              => "dynamic",
        'defaultedgetype'   => "directed",
        'timeformat'        => "date"
    };
    push( @{ $gexf->{ graph } }, $graph );
    
    my $attributes = { class => 'node', mode => 'static' };
    push( @{ $graph->{ attributes } }, $attributes );
    
    my $i = 0;
    while ( my ( $name, $type ) = each ( %{ $_media_static_gexf_attribute_types }  ) )
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
            id => $medium->{ media_id }, 
            label => $medium->{ name }, 
        };
        
        my $j = 0;
        while ( my ( $name, $type ) = each ( %{ $_media_static_gexf_attribute_types } ) )
        {
            push( @{ $node->{ attvalues }->{ attvalue } }, { for => $j++, value => $medium->{ $name } } );
        }    
        
        for my $story ( @{ $medium->{ stories } } )
        {
            my $story_date = substr( $story->{ publish_date }, 0, 10 );
            push( @{ $node->{ spells }->{ spell } }, { start => $story_date, end => $story_date } );
        }
                
        # $node->{ 'viz:color' } = [ get_media_type_color( $db, $medium->{ media_type } ) ];

        push( @{ $graph->{ nodes }->{ node } }, $node );
    }
            
    my $xml_dump = XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' );
    
    write_dump_file( $controversy, "controversy_media_${ weighting }", 'gexf', encode( 'utf8', $xml_dump ) );
}

sub generate_period_dump
{
    my ( $controversies_id, $start_date, $end_date, $period, $weightings ) = @_;
    
    my $dump_label = "${ period }_${ start_date }_${ end_date }";
    set_dump_label  ( $dump_label );
    
    print "generating $dump_label...\n";
    
    my $db = MediaWords::DB::connect_to_db;
    
    my $controversy = $db->find_by_id( 'controversies', $controversies_id ) ||
        die( "Unable to find controversy '$controversies_id'" );
    
    write_link_counts( $db, $controversy, $start_date, $end_date );

    write_controversy_links_dump( $db, $controversy, $start_date, $end_date );
    
    write_controversy_stories_dump( $db, $controversy, $start_date, $end_date );
    
    write_controversy_media_dump( $db, $controversy );
    
    write_controversy_media_links_dump( $db, $controversy );
 
    write_controversy_date_counts_dump( $db, $controversy, $start_date, $end_date );
    
    map { write_gexf_dump( $db, $controversy, $start_date, $end_date, $_ ) } @{ $weightings };
}

# decrease the given date to the latest monday equal to or before the date
sub truncate_to_monday
{
    my ( $date ) = @_;
    
    my $epoch_date = MediaWords::Util::SQL::get_epoch_from_sql_date( $date );
    my $week_day = ( localtime( $epoch_date ) )[ 6 ];

    # mod this to account for sunday, for which $week_day - 1 == -1
    my $days_offset = ( $week_day - 1 ) % 7;
    
    return MediaWords::Util::SQL::increment_day( $date, -1 * $days_offset );
}

# decrease the given date to the first day of the current month
sub truncate_to_start_of_month
{
    my ( $date ) = @_;
    
    my $epoch_date = MediaWords::Util::SQL::get_epoch_from_sql_date( $date );
    my $month_day = ( localtime( $epoch_date ) )[ 3 ];

    my $days_offset = $month_day - 1;
    
    return MediaWords::Util::SQL::increment_day( $date, -1 * $days_offset );    
}

sub generate_all_period_dumps
{
    my ( $controversies_id, $start_date, $end_date, $period, $weightings ) = @_;
    
    if ( $period eq 'overall' )
    {
        generate_period_dump( $controversies_id, $start_date, $end_date, $period, $weightings );
    }
    elsif ( $period eq 'weekly' )
    {
        my $w_start_date = truncate_to_monday( $start_date );
        while ( $w_start_date lt $end_date )
        {
            my $w_end_date = MediaWords::Util::SQL::increment_day( $w_start_date, 7 );
                        
            generate_period_dump( $controversies_id, $w_start_date, $w_end_date, $period, $weightings );
            
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
            
            generate_period_dump( $controversies_id, $m_start_date, $m_end_date, $period, $weightings );
            
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
    my ( $start_date, $end_date, $period, $weighting, $controversies_id );
    
    $period = 'all';
    
    Getopt::Long::GetOptions(
        "start_date=s" => \$start_date,
        "end_date=s" => \$end_date,
        "period=s" => \$period,
        "controversy=s" => \$controversies_id ) || return;

    $weighting = 'link';
        
    die( "Usage: $0 --start_date < start date > --end_date < end date > --period < overall|weekly|monthly|all > --controversy < id > >" )
        unless ( $start_date && $end_date && $period && $weighting && $controversies_id );
    
    my $all_periods = [ qw(overall weekly monthly) ];
    my $all_weightings = [ qw(link text text+link) ];
    
    die( "period must be all, overall, weekly, or monthly" ) if ( $period && !grep { $_ eq $period } ( 'all', @{ $all_periods } ) );

    die( "weighting must be all, link, text, or text+link" ) if ( !grep { $_ eq $weighting } ( 'all', @{ $all_weightings } ) );
    
    my $periods = ( $period eq 'all' ) ? $all_periods : [ $period ];
    
    for my $p ( @{ $periods } ) 
    {
        my $weightings = ( $weighting eq 'all' ) ? $all_weightings : [ $weighting ];
        generate_all_period_dumps( $controversies_id, $start_date, $end_date, $p, $weightings );
    }
}

main();

__END__
