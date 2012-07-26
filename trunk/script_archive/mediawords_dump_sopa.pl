#!/usr/bin/perl

# dump various sopa queries to csv

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Date::Format;
use XML::Simple;

use MediaWords::DB;
use MediaWords::Util::CSV;

my $_dump_version;
my $_start_date;
my $_end_date;

my $_media_static_gexf_attribute_types = {
    url => 'string',
    media_type => 'string',
    link_weight => 'float', 
    link_count => 'integer',
    story_count => 'integer',
    sentiment_58billion => 'integer', 
};

sub set_dates
{
    ( $_start_date, $_end_date ) = @_;
}

sub get_dates
{
    return ( $_start_date, $_end_date );
}

# write the results of the query as a csv
sub write_dump_as_csv
{
    my ( $db, $table, $query ) = @_;
    
    my ( $start_date, $end_date ) = get_dates();
    
    my $file = "${ table }_${ start_date }_${ end_date }.csv";
    
    replace_table_contents( $db, $table, $query );
    
    my $dump_version = get_dump_version( $db );
    
    my $res = $db->query( "select * from ${ table }_${ dump_version }" );
    
    my $fields = $res->columns;
    
    my $data = $res->hashes;
    
    my $fields = 
    
    my $csv_string = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $data, $fields );
    
    open( FILE, ">$file" ) || die( "Unable to open '$file' for writing: $!" );
    
    print FILE $csv_string;
    
    close( FILE );
}

sub write_link_counts
{
    my ( $db, $start_date, $end_date ) = @_;
    
    replace_table_contents( $db, 'sopa_story_link_counts_dump', 
        "select count(*) link_count, ref_stories_id from sopa_links_cross_media sl, stories s, stories r " . 
        "  where sl.stories_id = s.stories_id and sl.ref_stories_id = r.stories_id and " .
        "    ( s.publish_date between '$start_date' and '$end_date' or " . 
        "      r.publish_date between '$start_date' and '$end_date' ) " .
        "  group by ref_stories_id" );

    replace_table_contents( $db, 'sopa_story_outlink_counts_dump', 
        "select count(*) outlink_count, sl.stories_id from sopa_links_cross_media sl, stories s, stories r " . 
        "  where sl.stories_id = s.stories_id and sl.ref_stories_id = r.stories_id and " .
        "    ( s.publish_date between '$start_date' and '$end_date' or " . 
        "      r.publish_date between '$start_date' and '$end_date' ) " .
        "  group by sl.stories_id" );

}


sub write_sopa_stories_dump
{
    my ( $db ) = @_;
    
    my $tags = $db->query(
        "select * from tags t, tag_sets ts " .
        "  where t.tag_sets_id = ts.tag_sets_id and ts.name = 'sopa' and t.tag <> 'all'" )->hashes;
        
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
    
    my $dump_version = get_dump_version( $db );
    
    write_dump_as_csv( $db, 'sopa_stories_dump', <<END );
select distinct s.stories_id, s.title, s.url, s.publish_date, 
        m.name media_name, m.url media_url, m.media_id, ss.link_weight, 
        coalesce( lc.link_count, 0) link_count, coalesce( olc.outlink_count, 0) outlink_count, 
        coalesce( lc.link_count, 0) + coalesce( olc.outlink_count, 0) total_link_count, $tag_clause_list
	from stories s, media m, sopa_stories ss  
	    left join sopa_story_link_counts_dump_${ dump_version } as lc on ( ss.stories_id = lc.ref_stories_id )
	    left join sopa_story_outlink_counts_dump_${ dump_version } as olc on ( ss.stories_id = olc.stories_id )
	where ss.stories_id = s.stories_id and s.media_id = m.media_id and
        ( s.stories_id in ( 
            ( select sl.source_stories_id from sopa_links_dump_${ dump_version } sl ) union
            ( select sl.ref_stories_id from sopa_links_dump_${ dump_version } sl ) ) )
	order by s.publish_date;
END
}

      # ( s.stories_id in 
      #     ( select sls.stories_id from stories sls, sopa_links sl 
      #         where sls.stories_id = sl.stories_id and sls.publish_date between '$start_date' and '$end_date ' )  or
      #   s.stories_id in 
      #     ( select sls.stories_id from stories sls, sopa_links sl 
      #         where sls.stories_id = sl.ref_stories_id and sls.publish_date between '$start_date' and '$end_date ' ) )

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
	  and ( ss.publish_date between '$start_date' and '$end_date' or rs.publish_date between '$start_date' and '$end_date' )
END
}

sub write_sopa_media_dump
{
    my ( $db ) = @_;
    
    my $tags = $db->query(
        "select * from tags t, tag_sets ts " .
        "  where t.tag_sets_id = ts.tag_sets_id and ts.name = 'sopa' and t.tag <> 'all'" )->hashes;
        
    my $tag_fields = [];
    for my $tag ( @{ $tags } )
    {
        my $label = "tagged_" . lc( $tag->{ tag } );
        $label =~ s/[^[[:alnum:]]]/_/g;
        
        push( @{ $tag_fields}, "bool_or( $label ) $label" );
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
  where total_link_count > 0
  group by m.media_id, m.name, m.url
  order by sum( ssd.link_weight );    
END
}

sub write_sopa_media_links_dump
{
    my ( $db ) = @_;
    
    my $dump_version = get_dump_version( $db );
    
    write_dump_as_csv( $db, 'sopa_media_links_dump', <<END );
select source_media_id, ref_media_id, count(*) link_count from sopa_links_dump_${ dump_version } group by source_media_id, ref_media_id
END
}

sub write_sopa_date_counts_dump
{
    my ( $db, $start_date, $end_date ) = @_;
    
    my $tags = $db->query(
        "select * from tags t, tag_sets ts "  .
        "  where t.tag_sets_id = ts.tag_sets_id and ts.name = 'sopa'" )->hashes;
        
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
    
    write_dump_as_csv( $db, 'sopa_date_counts_dump', <<END );
select all_weeks.publish_week, $tag_fields_list
    from ( select distinct date_trunc( 'week', s.publish_date ) publish_week
             from stories s join sopa_stories ss on ( s.stories_id = ss.stories_id ) ) all_weeks
         $tag_queries_list
         where all_weeks.publish_week between '$start_date' and '$end_date'
         order by all_weeks.publish_week
END
}

sub get_dump_version
{
    my ( $db ) = @_;
    
    return $_dump_version if ( $_dump_version );

    my $last_media_dump = $db->query( 
        "select tablename from pg_tables where tablename like 'sopa_story_link_counts_dump_%' order by tablename desc limit 1" )->hash;
        
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
    
    die ( "table must end in 'dump'") if ( $table !~ /dump$/ );
    
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
        
    my $tags = $db->query(
        "select * from tags t, tag_sets ts "  .
        "  where t.tag_sets_id = ts.tag_sets_id and ts.name = 'sopa' and t.tag <> 'all'" )->hashes;
        
    map { $_media_static_gexf_attribute_types->{ "tagged_" . $_->{ tag } } = 'integer' } @{ $tags };
}

sub write_gexf_dump
{
    my ( $db, $start_date, $end_date ) = @_;
    
    my $dump_version = get_dump_version( $db );
    
    add_tags_to_gexf_attribute_types( $db );
    
    my $media = $db->query( 
        "select smd.* from sopa_media_dump_${ dump_version } smd where total_link_count > 0 order by link_count desc" )->hashes;
    my $media_links = $db->query( "select * from sopa_media_links_dump_${ dump_version }" )->hashes;
    my $stories = $db->query( 
        "select ssd.media_id, min( ssd.publish_date ) publish_date from sopa_stories_dump_${ dump_version } ssd " . 
        "  group by media_id, date_trunc( 'day', ssd.publish_date ) order by media_id, date_trunc( 'day', ssd.publish_date )" )->hashes;
        
    attach_stories_to_media( $stories, $media );
    
    my $gexf = { 
        'xmlns'                 => "http://www.gexf.net/1.2draft",
        'xmlns:xsi'             => "http://www.w3.org/2001/XMLSchema-instance",
        'xsi:schemaLocation'    => "http://www.gexf.net/1.2draft http://www.gexf.net/1.2draft/gexf.xsd",
        'version'               => "1.2"
    };
    
    my $meta = { 'lastmodifieddate' =>  Date::Format::time2str( '%Y-%m-%d', time ) };
    push( @{ $gexf->{ meta } }, $meta );
    
    push( @{ $meta->{ creator } }, 'Berkman Center' );
    push( @{ $meta->{ description } }, 'Media discussions of SOPA' );
    
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
    
    for my $medium ( @{ $media } )
    {
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
                
        push( @{ $graph->{ nodes }->{ node } }, $node );
    }
    
    my $k = 0;
    for my $media_link ( @{ $media_links } )
    {
        my $edge = { 
            id => $k++, 
            source => $media_link->{ source_media_id }, 
            target => $media_link->{ ref_media_id }, 
            weight => $media_link->{ link_count }
        };
        
        push( @{ $graph->{ edges }->{ edge } }, $edge );
    }

    open( FILE, ">sopa_media_${ start_date }_${ end_date }.gexf" ) || die( "Unable to open gexf file: $!" );
    
    binmode( FILE, 'utf8' );

    print FILE XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' );
    
    close( FILE );
}

sub main 
{
    my ( $start_date, $end_date ) = @ARGV;
    
    $start_date ||= '2006-01-01';
    $end_date ||= '2012-03-01';
    
    set_dates( $start_date, $end_date );
    
    my $db = MediaWords::DB::connect_to_db;
    
    write_link_counts( $db, $start_date, $end_date );

    write_sopa_links_dump( $db, $start_date, $end_date );
    
    write_sopa_stories_dump( $db );
    
    write_sopa_media_dump( $db );
    
    write_sopa_media_links_dump( $db );
 
    write_sopa_date_counts_dump( $db, $start_date, $end_date );
    
    write_gexf_dump( $db, $start_date, $end_date );
}

main();

__END__
