#!/usr/bin/env perl

# this is a daemon process that polls the word_cloud_topics table every minute to check for any pending
# word_cloud_topics and generates reports for any it finds.

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Encode;
use FileHandle;
use HTML::Entities;
use HTML::TagCloud;
use List::Util;
use URI::Escape;

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use constant MEDIA_SET_NAMES => ();

use constant NUM_CLOUD_TERMS    => 50;
use constant NUM_TIMELINE_TERMS => 10;

# global database handle
my $_db;

# global query term
my $_query;

# cache of p values
my $_p_cache;

# cache of time_slice list for timeline chart
my $_time_slices;

# cache order of words in between calls to get_p_cloud
my $_p_lookup;

# cache of set sizes for normalization of pr() queries
my $_set_size;

# cache google encoding lookup table
my $_google_chart_simple_encoding_lookup;

# cache of terms to make pages for
my $_term_pages;

# static html list of links to reuse for all pages
my $_links_html;

# UTILITY

# reset all of the above caches;
sub reset_caches
{
    $_query       = undef;
    $_p_cache     = undef;
    $_time_slices = undef;
    $_p_lookup    = undef;
    $_set_size    = undef;
    $_term_pages  = undef;
}

# open the file or die with an error
sub safe_file_open
{
    my $fh = new FileHandle( $_[ 0 ] );

    if ( !$fh )
    {
        die( "Unable to open file '$_[0]': $!" );
    }

    return $fh;
}

# get a tag hash for the given tag_set and tag
sub get_tag
{
    my ( $tag_set_name, $tag_name ) = @_;

    my $tag = $_db->query(
        "select t.* from tags t, tag_sets ts where t.tag_sets_id = ts.tag_sets_id and " . "    t.tag = ? and ts.name = ?",
        $tag_name, $tag_set_name )->hash;
    if ( !$tag )
    {
        die( "unknown tag $tag_set_name:$tag_name" );
    }

    return $tag;
}

# SOURCE FUNCTIONS

# get a list of sources matching the given tag.  each source can be either a feed, a media, or a tag
# each source returned is a hash in the form of:
# { type => <feeds|media|tags>,
#   name => <feeds.name|media.name|tags.tag>,
#   id => <feeds_id|media_id|tags_id> }
#
# for feeds/media, the id is the id of a feed or media tag that points to the
# feeds/media to be included in the source.
#
# for tags, the id is a space separated list of tags as "<tag set name>:<tag name> ..."
sub get_sources
{
    my ( $type, $id ) = @_;

    if ( ( $type eq 'feeds' ) || ( $type eq 'media' ) )
    {
        return $_db->query(
            "select ?::text as type, name, ${type}_id as id " . "  from ${type} where ${type}_id in " .
              "    (select ${type}_id from ${type}_tags_map " . "      where tags_id = ?)",
            $type, $id
        )->hashes;
    }
    elsif ( $type eq 'tags' )
    {
        my $sources;
        for my $tag ( split( /\s+/, $id ) )
        {
            my ( $tag_set_name, $tag_name ) = split( ":", $tag );
            push(
                @{ $sources },
                $_db->query(
                    "select 'tags' as type, t.tag as name, t.tags_id as id from tags t, tag_sets ts " .
                      "  where ts.tag_sets_id = t.tag_sets_id and ts.name = ? and t.tag = ?",
                    $tag_set_name, $tag_name
                  )->hash
            );
        }

        return $sources;
    }
    else
    {
        die( "Unknown source type: $type" );
    }
}

# return a sql where clause and join 'on' clause for feeds_stories_map fsm that matches the stories from the given sources
# of type either 'feed' or 'media'
sub get_story_where_and_join
{
    my ( $type, $tags_id ) = @_;

    my ( $type_clause, $type_join );

    if ( $type eq 'media' )
    {
        $type_clause = "s.media_id in (select media_id from media_tags_map where tags_id = $tags_id)";
        $type_join   = "fsm.feeds_id = -1";
    }
    elsif ( $type eq 'feeds' )
    {
        $type_clause =
          "fsm.stories_id = fsm.stories_id and fsm.feeds_id in " .
          "(select feeds_id from feeds_tags_map where tags_id = $tags_id)";
        $type_join = "s.stories_id = fsm.stories_id";
    }
    else
    {
        die( "Unknown source type: $type" );
    }

    return ( $type_clause, $type_join );
}

# generate a title describing the source
sub get_encoded_source_title
{
    my ( $source ) = @_;

    if ( $source->{ type } eq 'all' )
    {
        return "All Sources";
    }
    elsif ( $source->{ type } eq 'tags' )
    {
        my $name = $source->{ name };

        $name =~ s/_/ /g;
        $name =~ s/(\w\S*)/\u\L$1/g;

        return "Set: " . encode_entities( $name );
    }
    elsif ( ( $source->{ type } eq 'media' ) || ( $source->{ type } eq 'feeds' ) )
    {
        return "Source: " . encode_entities( $source->{ name } );
    }
    else
    {
        die( "uknown source type " . $source->{ type } );
    }

}

# get a sql where clause that restricts the query_words rows to the given source
sub get_source_clause
{
    my ( $source ) = @_;

    if ( $source->{ type } eq 'all' )
    {
        return '1 = 1';
    }
    elsif ( $source->{ type } eq 'tags' )
    {
        return "( ( ( media_id in ( select media_id from media_tags_map mtm where tags_id = $source->{id} ) ) and " .
          "    ( feeds_id is null ) ) or " .
          "  ( feeds_id in ( select feeds_id from feeds_tags_map ftm where tags_id = $source->{id} ) ) )";
    }
    elsif ( ( $source->{ type } eq 'media' ) || ( $source->{ type } eq 'feeds' ) )
    {
        return $source->{ type } . "_id = " . $source->{ id };
    }
    else
    {
        die( "uknown set type " . $source->{ type } );
    }
}

# TERM PAGES

# get a link to a term page
sub get_term_file
{
    my ( $stem, $term ) = @_;

    $_term_pages->{ $stem } = $term;

    $stem =~ s~/~~g;

    return "terms_$stem.html";
}

# get a list of stories that match a given term within a given source
sub get_term_stories
{
    my ( $source_tags_id, $stem, $term, $start_date, $end_date ) = @_;

    my ( $type_clause, $type_join ) = get_story_where_and_join( 'media', $source_tags_id );

    my $media_query =
      "select m.name, s.title, s.url, " . "    cast( date_trunc('day', s.publish_date) as date ) as time_slice " .
      "  from stories s left join feeds_stories_map fsm on ($type_join), story_vectors sv, media m " .
      "  where s.stories_id = sv.stories_id " . "    and sv.vector @@ plainto_tsquery('english', '$_query $term') " .
      "    and s.publish_date >= date '$start_date' and s.publish_date <= date '$end_date' " .
      "    and $type_clause and s.media_id = m.media_id";

    my ( $type_clause, $type_join ) = get_story_where_and_join( 'feeds', $source_tags_id );

    my $feeds_query =
      "select f.name, s.title, s.url, " . "    cast( date_trunc('day', s.publish_date) as date ) as time_slice " .
      "  from stories s left join feeds_stories_map fsm on ($type_join), feeds f, story_vectors sv " .
      "  where s.stories_id = sv.stories_id " . "    and sv.vector @@ plainto_tsquery('english', '$_query $term') " .
      "    and s.publish_date >= date '$start_date' and s.publish_date <= date '$end_date' " .
      "    and $type_clause and f.feeds_id = fsm.feeds_id";

    return $_db->query( "($feeds_query) union all ($media_query) order by time_slice" )->hashes;
}

# generate html list of stories about the term
sub generate_term_stories_html
{
    my ( $stories ) = @_;

    my $html;
    my $prev_day = '';
    for my $story ( @{ $stories } )
    {
        if ( $prev_day ne $story->{ time_slice } )
        {
            if ( $prev_day )
            {
                $html .= "</ul>\n";
            }

            $html .= "<p><b>$story->{time_slice}</b></p>\n<ul>\n";
        }

        my $hs             = HTML::Strip->new();
        my $enc_title      = encode_entities( encode( 'utf8', $hs->parse( $story->{ title } || '' ) ) );
        my $enc_media_name = encode_entities( encode( 'utf8', $story->{ name } ) );

        $html .= qq~<li><b>$enc_media_name:</b> <a href="$story->{url}">$enc_title</a></li>\n~;

        $prev_day = $story->{ time_slice };
    }

    $html .= "</ul>\n";

    return $html;
}

# get the top num source names with the most stories in the list
sub get_top_story_source_names
{
    my ( $stories, $num ) = @_;

    my $source_name_counts;
    for my $story ( @{ $stories } )
    {
        $source_name_counts->{ $story->{ name } }++;
    }

    my $source_names = [];
    while ( my ( $name, $count ) = each( %{ $source_name_counts } ) )
    {
        push( @{ $source_names }, [ $name, $count ] );
    }

    my @sorted_names = sort { $b->[ 1 ] <=> $a->[ 1 ] } @{ $source_names };

    my @names = map { $_->[ 0 ] } @sorted_names;

    if ( @names > $num )
    {
        @names = @names[ 0 .. ( $num - 1 ) ];
    }

    return \@names;
}

# generate timeline chart of use of the term over time
sub generate_term_timeline
{
    my ( $stories ) = @_;

    my $source_names = get_top_story_source_names( $stories, NUM_TIMELINE_TERMS );

    if ( !$_time_slices )
    {
        $_time_slices = $_db->query( "select distinct time_slice from query_words order by time_slice asc" )->flat;
    }

    my $story_counts;
    for my $story ( @{ $stories } )
    {
        $story_counts->{ $story->{ name } }->{ $story->{ time_slice } }++;
    }

    my $time_slicely_data = [];
    for my $source_name ( @{ $source_names } )
    {

        my $data;
        for my $time_slice ( @{ $_time_slices } )
        {
            push( @{ $data }, $story_counts->{ $source_name }->{ $time_slice } );
        }

        push( @{ $time_slicely_data }, $data );
    }

    my $chart_url = generate_timeline_chart_url( $_time_slices, $source_names, $time_slicely_data );

    my $html = qq~
<img src="$chart_url" />
~;

    return $html;
}

# generate term page
sub generate_term_page
{
    my ( $source_tags_id, $stem, $term, $start_date, $end_date ) = @_;

    my $stories = get_term_stories( $source_tags_id, $stem, $term, $start_date, $end_date );

    my $term_stories_chart_html = generate_term_timeline( $stories );

    my $term_stories_html = generate_term_stories_html( $stories );

    my $enc_query = encode_entities( $_query );

    my $enc_term = encode_entities( $term );

    my $term_file = get_term_file( $stem );

    my $fh = safe_file_open( ">$term_file" );

    $fh->print(
        qq~
<html>
<head>
<title>$enc_query stories about $enc_term - Media Cloud Topic Explorer</title>
<style type="text/css">
a { color: 32588F; text-decoration: none;}
</style>
</head>
<body>
<h2>Media Cloud Topic Explorer: $enc_query stories about $enc_term</h2>

<h3>Number of stories including '$enc_query' and '$enc_term'</h3>

$term_stories_chart_html

<h3>Stories including '$enc_query' and '$enc_term'</h3>

$term_stories_html

<h3>Explore Other Sources</h3>

$_links_html

</body>

</html>
~
    );

    $fh->close();
}

# generate term pages for each page in $_term_pages
sub generate_term_pages
{
    my ( $source_tags_id, $start_date, $end_date ) = @_;

    while ( my ( $stem, $term ) = each( %{ $_term_pages } ) )
    {
        generate_term_page( $source_tags_id, $stem, $term, $start_date, $end_date );
    }

}

# GENERATE_CHARTS

# get cached value of p for args
sub get_cached_p
{
    my ( $source, $pr_source, $num, $stem, $group_by_time_slice ) = @_;

    my $key = Dumper( $source, $pr_source, $stem, $group_by_time_slice );

    if ( my $c = $_p_cache->{ $key } )
    {
        if ( $c->{ num } >= $num )
        {
            if ( $c->{ num } > $num )
            {
                return [ @{ $c->{ p } }[ 0 .. $num - 1 ] ];
            }
            return $c->{ p };
        }
    }

    return undef;
}

# set the cache for p
sub set_cached_p
{
    my ( $p, $source, $pr_source, $num, $stem, $group_by_time_slice ) = @_;

    my $key = Dumper( $source, $pr_source, $stem, $group_by_time_slice );

    my $c = $_p_cache->{ $key };

    if ( !$c || ( $c->{ num } < $num ) )
    {
        $_p_cache->{ $key }->{ num } = $num;
        $_p_cache->{ $key }->{ p }   = $p;
    }
}

# get a sql clause that restricts the terms within query words
sub get_stem_clause
{
    my ( $stem_field, $stem ) = @_;

    if ( $stem )
    {
        return "$stem_field = " . $_db->{ dbh }->quote( $stem );
    }
    else
    {
        return "1=1";
    }
}

# get the terms with the highest pr(set, pr_set)
sub get_pr
{
    my ( $source, $pr_source, $num, $stem, $group_by_time_slice ) = @_;

    my $a_m = get_source_clause( $source );
    my $b_m = get_source_clause( $pr_source );

    my $stem_clause = get_stem_clause( 'stem', $stem );

    my ( $time_slice_field, $a_time_slice_field, $time_slice_join, $time_slice_group ) = ( '', '', '', '' );
    if ( $group_by_time_slice )
    {
        $time_slice_field   = ', time_slice';
        $a_time_slice_field = ', a.time_slice';
        $time_slice_join    = 'and a.time_slice = b.time_slice';
        $time_slice_group   = 'time_slice, ';
    }

    #$_set_size->{$a_m} ||= $_db->query("select sum(term_count) from query_words where $a_m")->flat->[0] || 1;
    #$_set_size->{$b_m} ||= $_db->query("select sum(term_count) from query_words where $b_m")->flat->[0];

    #my $normalization_factor = $_set_size->{$b_m} / (5 * $_set_size->{$a_m});
    #my $pr_equation = "( ( ( log(a.p) * a.p ) / (coalesce(b.p, 1) + (a.p * $normalization_factor)) ) * 100 )";

    #my $pr_equation = "( ( log(a.p) * a.p ) / coalesce(b.p, 1) )";

    my $pr_equation = "( ( a.p::numeric * a.p::numeric)::numeric  / coalesce(b.p, 1)::numeric )::numeric";

    my $words =
      $_db->query( "select $pr_equation as term_count, a.term, a.stem $a_time_slice_field " .
          "from (select sum(term_count * query_rank) as p, min(term) as term, stem $time_slice_field " .
          "    from query_words where $a_m and $stem_clause group by $time_slice_group stem) a " .
          "left join (select sum(term_count * query_rank) as p, min(term) as term, stem $time_slice_field " .
          "    from query_words where $b_m /*and not $a_m*/ and $stem_clause group by $time_slice_group stem) b " .
          "    on a.stem = b.stem $time_slice_join " . "where $pr_equation >= 1 " .
          "order by $time_slice_group term_count desc $time_slice_field limit $num" )->hashes;

    set_cached_p( $words, @_ );

    return $words;
}

# get p(source) if only set is passed or pr(source, pr_source) if two sources are passed
sub get_p
{
    my ( $source, $pr_source, $num, $stem, $group_by_time_slice ) = @_;

    if ( my $p = get_cached_p( @_ ) )
    {
        return $p;
    }

    if ( $pr_source )
    {
        return get_pr( @_ );
    }

    my $source_clause = get_source_clause( $source );

    my $stem_clause = get_stem_clause( 'stem', $stem );

    my $time_slice_field = '';
    if ( $group_by_time_slice )
    {
        $time_slice_field = ', time_slice';
    }

    my $words =
      $_db->query( "select sum(term_count * query_rank)::numeric as term_count, stem, " .
          "    min(term) as term $time_slice_field from query_words " . "  where $source_clause and $stem_clause " .
          "  group by stem $time_slice_field order by term_count desc $time_slice_field limit $num" )->hashes;

    set_cached_p( $words, @_ );

    return $words;

}

# generate a word cloud for p(source) or pr(source, pr_source)
sub generate_p_cloud
{
    my ( $source, $pr_source ) = @_;

    my $words = get_p( $source, $pr_source, NUM_CLOUD_TERMS );

    my $cloud = HTML::TagCloud->new;

    # make a lookup of tags in the p(x) map so that we can bold differences in the pr(x) maps
    if ( !$pr_source )
    {
        $_p_lookup = {};
    }

    my $i = 0;
    for my $word ( @{ $words } )
    {

        # add google search for term
        #my $url = 'http://google.com/search?q=' . uri_escape($_query) . '+' . uri_escape($word->{term});
        #if ($set->{type} eq 'medium') {
        #    $url .= '+' . uri_escape('site:' . $set->{medium}->{url});
        #}
        my $url = get_term_file( $word->{ stem }, $word->{ term } );

        my $t = $word->{ term };

        # keep track of which terms were shown in the p cloud so that we can highlight the new ones in the pr clouds
        $i++;
        if ( $pr_source )
        {
            my $p_pos = $_p_lookup->{ $word->{ term } };
            if ( !$p_pos || ( $p_pos > $i + 10 ) )
            {
                $t = "<span style='color:001133'>$t</span>";
            }
        }
        else
        {
            $_p_lookup->{ $word->{ term } } = $i;
        }

        $cloud->add( $t, $url, List::Util::max( $word->{ term_count }, 1 ) );

    }
    my $chart_html = $cloud->html( NUM_CLOUD_TERMS );

    my $html = qq~
<div id="word_cloud">
$chart_html
</div>
~;

    return $html;
}

# get lookup table for google chart simple encoding values
# http://code.google.com/apis/chart/formats.html#simple
sub get_google_chart_simple_encoding_lookup
{
    my ( $v ) = @_;

    if ( !$_google_chart_simple_encoding_lookup )
    {
        my $i = 0;
        for my $c ( ( 'A' .. 'Z' ), ( 'a' .. 'z' ), ( 0 .. 9 ) )
        {
            $_google_chart_simple_encoding_lookup->{ $i++ } = $c;
        }
    }

    return $_google_chart_simple_encoding_lookup;
}

# generate the google chart url for a timeline of story term counts
# eg:
#http://chart.apis.google.com/chart?&cht=ls&chd=t:0,30,60,70,90,95,100|20,30,40,50,60,70,80|10,30,40,45,52&chco=ff0000,00ff00,0000ff&chs=250x150&chdl=NASDAQ|FTSE100|DOW
sub generate_timeline_chart_url
{
    my ( $time_slices, $terms, $time_slicely_data ) = @_;

    my $params = [];

    # data scaling
    my $max = 1;
    for my $counts ( @{ $time_slicely_data } )
    {
        for my $count ( @{ $counts } )
        {
            if ( !$max || ( $count > $max ) )
            {
                $max = $count;
            }
        }
    }

    # data
    # normalize to 60 to be able to use simple encoding (which we need to be able to fit all the data into the url)
    my $enc = get_google_chart_simple_encoding_lookup();
    push(
        @{ $params },
        'chd=s:' . join(
            ',',
            map {
                join( '', map { $enc->{ int( $_ * ( 60 / $max ) ) } } @{ $_ } )
              } @{ $time_slicely_data }
        )
    );

    # legend for lines
    push( @{ $params }, 'chdl=' . join( '|', map { s/\|/-/g; uri_escape( $_ ); } @{ $terms } ) );

    # legend for x axis
    my $days;
    if ( @{ $time_slices } <= 4 )
    {
        $days = $time_slices;
    }
    else
    {
        for ( my $n = 0 ; $n < 3 ; $n++ )
        {
            my $i = $n * ( @{ $time_slices } / 3 );
            push( @{ $days }, $time_slices->[ int( $i ) ] );
        }
        push( @{ $days }, $time_slices->[ @{ $time_slices } - 1 ] );
    }

    push( @{ $params }, 'chxt=x&chxl=0:|' . join( '|', @{ $days } ) );

    # size
    push( @{ $params }, 'chs=600x250' );

    # type
    push( @{ $params }, 'cht=lc' );

    # color
    my $colors = [ qw(ff0000 00ff00 0000ff ff8888 88ff88 8888ff 88ffff ff88ff ffff88 888888) ];
    while ( @{ $colors } > @{ $terms } )
    {
        pop( @{ $colors } );
    }
    push( @{ $params }, 'chco=' . join( ',', @{ $colors } ) );

    my $url = 'http://chart.apis.google.com/chart?' . join( '&', @{ $params } );

    print STDERR "google chart url: $url\n";

    return $url;
}

# generate timeline of top ten most prevalent terms every time_slice over the entire timespan
sub generate_p_timeline
{
    my ( $source, $pr_source ) = @_;

    my $words = get_p( $source, $pr_source, NUM_TIMELINE_TERMS );

    if ( !$_time_slices )
    {
        $_time_slices = $_db->query( "select distinct time_slice from query_words order by time_slice asc" )->flat;
    }

    my $time_slicely_data = [];
    for my $word ( @{ $words } )
    {
        my $time_slice_counts = get_p( $source, $pr_source, scalar( @{ $_time_slices } ), $word->{ stem }, 1 );

        my $data;
        for my $time_slice ( @{ $_time_slices } )
        {
            my $count = 0;
            for my $time_slice_count ( @{ $time_slice_counts } )
            {
                if ( $time_slice_count->{ time_slice } eq $time_slice )
                {
                    $count = int( 100 * $time_slice_count->{ term_count } );
                    last;
                }
            }
            push( @{ $data }, $count );
        }

        push( @{ $time_slicely_data }, $data );
    }

    my $terms = [ map { $_->{ term } } @{ $words } ];

    my $chart_url = generate_timeline_chart_url( $_time_slices, $terms, $time_slicely_data );

    my $html = qq~
<img src="$chart_url" />
~;

    return $html;

}

# generate word cloud and timeline charts for the prevalence of the query for the given set of stories.
# use p(x) if there is only one set and pr(x, y) if there are two sets
sub generate_p_charts
{
    my ( $source, $pr_source ) = @_;

    my $source_title = get_encoded_source_title( $source );

    my $title;
    if ( $pr_source )
    {
        my $pr_source_title = get_encoded_source_title( $pr_source );
        $title = "Words that appear more often in $source_title than in $pr_source_title:";
    }
    else
    {
        $title = "Words that appear most often in $source_title:";
    }

    my $terms = get_p( $source, $pr_source, NUM_CLOUD_TERMS );
    if ( !@{ $terms } )
    {
        return "<h3>$title</h3><p>(not enough data to generate results)</p>\n";
    }

    my $cloud = generate_p_cloud( $source, $pr_source );
    my $timeline = generate_p_timeline( $source, $pr_source );

    my $html = qq~
<h3>$title</h3>
<div id='p_charts'>
<table border='0'>
<tr>
<td width="100%">$cloud</trd>
<td>$timeline</td>
</tr>
</table>
</div>    
~;

    return $html;

}

# GENERATE LINKS

# get the filename for the source
sub get_source_file
{
    my ( $source ) = @_;

    my $name = join( '_', $source->{ type }, $source->{ id }, $source->{ name } ) . ".html";

    $name =~ s~/~~g;

    return $name;
}

# get file for pr comparison of two sources
sub get_pr_file
{
    my ( $source, $pr_source ) = @_;

    my $name = join( '_',
        'pr',
        $source->{ type },
        $source->{ id },
        $source->{ name },
        $pr_source->{ type },
        $pr_source->{ id },
        $pr_source->{ name } ) .
      ".html";

    $name =~ s~/~~g;

    return $name;
}

# get the filename for the comparator between the source

# generate html for a list of links to all source pages
sub generate_links
{
    my ( $sources ) = @_;

    my $html = "<a href='index.html'>All Sources</a>\n|\n";

    for my $source ( @{ $sources } )
    {
        my $file = get_source_file( $source );
        $html .= "<a href='" . uri_escape( $file ) . "'>" . get_encoded_source_title( $source ) . "</a>\n|\n";
    }

    return $html;
}

# generate html for a comparative pr link
sub generate_pr_link
{
    my ( $source, $pr_source ) = @_;

    my $file = get_pr_file( $source, $pr_source );

    return "<a href='" . uri_escape( $file ) . "'>" . get_encoded_source_title( $pr_source ) . "</a>";
}

# PRINT PAGES

# print the page with header and footer
sub print_page
{
    my ( $file, $title, $charts, $pr_links ) = @_;

    my $fh = safe_file_open( ">$file" );

    my $charts_html = join( "\n", map { "<div id='chart_set'>$_</div>" } @{ $charts } );

    $fh->print(
        qq~
<html>
<head>
<title>$_query stories in $title - Media Cloud Topic Explorer</title>
<style type="text/css">
#htmltagcloud {
  text-align:  center; 
  line-height: 1; 
}
a { color: 32588F; text-decoration: none;}
span.tagcloud0 { font-size: 12px;}
span.tagcloud1 { font-size: 13px;}
span.tagcloud2 { font-size: 14px;}
span.tagcloud3 { font-size: 15px;}
span.tagcloud4 { font-size: 16px;}
span.tagcloud5 { font-size: 17px;}
span.tagcloud6 { font-size: 18px;}
span.tagcloud7 { font-size: 19px;}
span.tagcloud8 { font-size: 20px;}
span.tagcloud9 { font-size: 21px;}
span.tagcloud10 { font-size: 22px;}
span.tagcloud11 { font-size: 23px;}
span.tagcloud12 { font-size: 24px;}
span.tagcloud13 { font-size: 25px;}
span.tagcloud14 { font-size: 26px;}
span.tagcloud15 { font-size: 27px;}
span.tagcloud16 { font-size: 28px;}
span.tagcloud17 { font-size: 29px;}
span.tagcloud18 { font-size: 30px;}
span.tagcloud19 { font-size: 31px;}
span.tagcloud20 { font-size: 32px;}
span.tagcloud21 { font-size: 33px;}
span.tagcloud22 { font-size: 34px;}
span.tagcloud23 { font-size: 35px;}
span.tagcloud24 { font-size: 36px;}
</style>
</head>
<body>
<h2>Media Cloud Topic Explorer: $_query stories in $title </h2>

<div id="charts">
$charts_html
</div>


<div id="links">
~
    );

    if ( $pr_links )
    {
        my $pr_links_html = join( "\n|\n", @{ $pr_links } );

        $fh->print(
            qq~
<h3>Compare to Another Source:</h3>

$pr_links_html
~
        );
    }

    $fh->print(
        qq~


<h3>Explore Other Sources</h3>

$_links_html

</div>

</body>
</html>
~
    );

    $fh->close();
}

# GENERATE PAGES

# generate pr page to compare two sources
sub generate_pr_page
{
    my ( $source, $pr_source, $pr_links ) = @_;

    my $pr = generate_p_charts( $source,    $pr_source );
    my $rp = generate_p_charts( $pr_source, $source );

    my $file = get_pr_file( $source, $pr_source );

    my $title = get_encoded_source_title( $source ) . " v. " . get_encoded_source_title( $pr_source );

    print_page( $file, $title, [ $pr, $rp ], $pr_links );
}

# generate a page for a source (feed/media/tag)
sub generate_source_page
{
    my ( $source, $all_sources ) = @_;

    my $p = generate_p_charts( $source );
    my $pr = generate_p_charts( $source, { type => 'all' } );

    my $prs      = [];
    my $pr_links = [];

    $all_sources =
      [ grep { !( ( $_->{ type } eq $source->{ type } ) && ( $_->{ id } eq $source->{ id } ) ) } @{ $all_sources } ];

    for my $pr_source ( @{ $all_sources } )
    {
        push( @{ $pr_links }, generate_pr_link( $source, $pr_source ) );
    }

    for my $pr_source ( @{ $all_sources } )
    {
        generate_pr_page( $source, $pr_source, $pr_links );
    }

    my $file = get_source_file( $source );

    print_page( $file, get_encoded_source_title( $source ), [ $p, $pr ], [ @{ $pr_links } ] );
}

# generate index page with summary p and links to all source pages
sub generate_index_page
{

    my $source = { type => 'all' };

    my $p_all = generate_p_charts( $source );

    print_page( "index.html", get_encoded_source_title( $source ), [ $p_all ] );
}

# return the query that inserts rows into the query_words table.
# if table is 'media', include stories in a media with a word_cloud:${tag_name} tag and group by media id.
# if table is 'feeds', include stories in a feed with the word_cloud:${tag_name} tag and group by feed id.
sub insert_query_words
{
    my ( $term_table, $type, $type_tags_id, $query, $start_date, $end_date ) = @_;

    my ( $type_clause, $type_join ) = get_story_where_and_join( $type, $type_tags_id );

    $_db->query(
        "insert into query_words " . "  select min(sw.term) as term, sw.stem, sum(stem_count) as term_count_raw, 0, 0, " .
          "    s.media_id, fsm.feeds_id, cast(date_trunc('day', s.publish_date) as date) as time_slice, " .
          "    sum(ts_rank(sv.vector, plainto_tsquery('english', '$query'), 1)) as query_rank  " .
          "  from stories s left join feeds_stories_map fsm on ($type_join), story_vectors sv, $term_table sw " .
          "  where s.stories_id = sv.stories_id and s.stories_id = sw.stories_id and " .
          "    s.publish_date >= date '$start_date' and s.publish_date <= date '$end_date' and " .
          "    sv.vector @@ plainto_tsquery('english', '$query') and " . "    $type_clause " .
          "  group by s.media_id, fsm.feeds_id, time_slice, sw.stem" );
}

# generate a temporary table to hold the word counts for stories that match the query by media_id and time_slice
# this intermediate table is used to generate all of the p and pr counts above
sub generate_query_words_table
{
    my ( $term_table, $source_tags_id, $query, $start_date, $end_date ) = @_;

    my $query_words = split( /\s+/, $query );

    if ( !$query )
    {
        die( "no query" );
    }

    $_db->query( "create temporary table query_words (" .
          "    term text, stem text, term_count_raw int, term_count_norm int, term_count int, " .
          "    media_id int, feeds_id int, time_slice date, query_rank float)" );

    # $_db->query("truncate table query_words");
    # eval {
    #     $_db->query("drop index query_words_mw");
    #     $_db->query("drop index query_words_t");
    # };

    insert_query_words( $term_table, 'media', $source_tags_id, $query, $start_date, $end_date );
    insert_query_words( $term_table, 'feeds', $source_tags_id, $query, $start_date, $end_date );

    $_db->query( "create index query_words_mw on query_words(media_id, time_slice)" );
    $_db->query( "create index query_words_t on query_words(media_id, stem)" );

    #set normalized term_count
    $_db->query( "update query_words as qw " .
          "  set term_count_norm = greatest ( 1, term_count_raw * ( 2000000000 / q.source_term_count ) ) " .
          "  from (select time_slice, media_id, feeds_id, greatest(500, sum(term_count_raw)) as source_term_count " .
          "      from query_words group by media_id, feeds_id, time_slice) q " .
          "  where q.time_slice = qw.time_slice and q.media_id = qw.media_id " .
          "    and coalesce(-1, q.feeds_id) = coalesce(-1, qw.feeds_id)" );

    # marke query_rank be between 0 and 1
    $_db->query( "update query_words set query_rank = ( query_rank / ( query_rank + 1 ) )" );

    $_db->query( "update query_words set term_count = term_count_norm" );

    $_db->query( "analyze query_words" );

}

# generate a report for the given query
sub generate_report
{
    my ( $topic_dir, $term_table, $source_tags_id, $set_tags, $query, $start_date, $end_date ) = @_;

    reset_caches();

    if ( !( -d $topic_dir ) && !mkdir( $topic_dir ) )
    {
        die( "Unable to make directory '$topic_dir': $!" );
    }

    chdir( $topic_dir );

    $source_tags_id ||= get_tag( 'word_cloud', 'default' )->{ tags_id };
    $set_tags ||= 'media_type:blogs media_type:newspapers';

    generate_query_words_table( $term_table, $source_tags_id, $query, $start_date, $end_date );

    my $media_sources = get_sources( 'media', $source_tags_id );
    my $feeds_sources = get_sources( 'feeds', $source_tags_id );
    my $set_sources   = get_sources( 'tags',  $set_tags );

    my $sources = [ @{ $set_sources }, sort { $a->{ name } cmp $b->{ name } } ( @{ $media_sources }, @{ $feeds_sources } ) ];

    $_query = $query;

    $_links_html = generate_links( $sources );

    generate_index_page();

    for my $source ( @{ $sources } )
    {
        generate_source_page( $source, $sources );
    }

    generate_term_pages( $source_tags_id, $start_date, $end_date );
}

# (re)connect to db
sub reconnect_to_db
{
    $_db = MediaWords::DB::connect_to_db();
}

# start a polling daemon, generating reports from word_cloud_topics as they appear in the db
sub generate_reports_from_db
{
    my ( $base_directory, $base_url ) = @_;

    while ( 1 )
    {
        reconnect_to_db();

        my $topics =
          $_db->query( "select * from word_cloud_topics where state = 'pending' order by word_cloud_topics_id" )->hashes;
        for my $topic ( @{ $topics } )
        {
            $_db->query( "update word_cloud_topics set state = 'generating' where word_cloud_topics_id = ?",
                $topic->{ word_cloud_topics_id } );

            my $topic_dir = "$base_directory/" . $topic->{ word_cloud_topics_id };

            generate_report(
                $topic_dir,
                'story_' . $topic->{ type },
                $topic->{ source_tags_id },
                $topic->{ set_tag_names },
                $topic->{ query },
                $topic->{ start_date },
                $topic->{ end_date }
            );

            my $topic_url = "$base_url/" . $topic->{ word_cloud_topics_id };
            $_db->query( "update word_cloud_topics set state = 'completed', url = ? where word_cloud_topics_id = ?",
                $topic_url, $topic->{ word_cloud_topics_id } );

            reconnect_to_db();
        }

        if ( !@{ $topics } )
        {
            sleep( 60 );
        }
    }
}

sub main
{

    if ( @ARGV == 2 )
    {
        generate_reports_from_db( @ARGV );
    }
    elsif ( @ARGV == 7 )
    {
        reconnect_to_db();
        generate_report( @ARGV );
    }
    else
    {
        print( "usage: mediawords_generate_topic_reports.pl " .
              "<directory> ( ( <url> ) | ( <term__type> <source_tags_id> <set_tags> <query> <start_date> <end_date> ) )\n" );
        exit 1;
    }
}

main();
