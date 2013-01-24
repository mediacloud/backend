#!/usr/bin/env perl

# this is a daemon process that polls the word_cloud_topics table every minute to check for any pending
# word_cloud_topics and generates reports for any it finds.
#
# this version generates a report based on the words within the sources that are in the same sentence as
# the specified word

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
use MediaWords::Languages::Language;
use List::Util;
use URI::Escape;

use DBIx::Simple::MediaWords;
use HTML::StripPP;
use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# number of terms to include in each word cloud
use constant NUM_CLOUD_TERMS => 50;

# number of terms to inlude in each timeline
use constant NUM_TIMELINE_TERMS => 10;

# score each source as having at least this many sentences
use constant MIN_SOURCE_SENTENCES => 25;

# max possible p for any given term
use constant MAX_P => .20;

# global database handle
my $_db;

# global query term
my $_query;

# global language code
my $_language_code;

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
sub reset_caches()
{
    $_query         = undef;
    $_language_code = undef;
    $_p_cache       = undef;
    $_time_slices   = undef;
    $_p_lookup      = undef;
    $_set_size      = undef;
    $_term_pages    = undef;
}

# open the file or die with an error
sub safe_file_open($)
{
    my $fh = new FileHandle( $_[ 0 ] );

    if ( !$fh )
    {
        die( "Unable to open file '$_[0]': $!" );
    }

    $fh->binmode( ':utf8' );

    return $fh;
}

# get the stem for the given word
sub get_stem($$)
{
    my ( $query, $language_code ) = @_;

    my $lang  = MediaWords::Languages::Language::language_for_code( $language_code );
    my $words = [ $query ];
    my $stems = $lang->stem( $words );
    if ( !@{ $stems } )
    {
        die( "failed to find a stem for $query" );
    }

    return $stems->[ 0 ];
}

# get a tag hash for the given tag_set and tag
sub get_tag($$)
{
    my ( $tag_set_name, $tag_name ) = @_;

    my $tag = $_db->query(
        <<EOF,
        SELECT t.*
        FROM tags AS t,
             tag_sets AS ts
        WHERE t.tag_sets_id = ts.tag_sets_id
              AND t.tag = ?
              AND ts.name = ?
EOF
        $tag_name, $tag_set_name
    )->hash;
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
sub get_sources($$)
{
    my ( $type, $id ) = @_;

    if ( ( $type eq 'feeds' ) || ( $type eq 'media' ) )
    {
        return $_db->query(
            <<EOF,
            SELECT ?::text AS type,
                   name,
                   ${type}_id AS id
            FROM ${type}
            WHERE ${type}_id IN (
                SELECT ${type}_id
                FROM ${type}_tags_map
                WHERE tags_id = ?
            )
EOF
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
                    <<EOF,
                    SELECT 'tags' AS type,
                           t.tag AS name,
                           t.tags_id AS id
                    FROM tags AS t,
                         tag_sets AS ts
                    WHERE ts.tag_sets_id = t.tag_sets_id
                          AND ts.name = ?
                          AND t.tag = ?
EOF
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
sub get_story_where_and_join($$)
{
    my ( $type, $tags_id ) = @_;

    my ( $type_clause, $type_join );

    if ( $type eq 'media' )
    {
        $type_clause = "s.media_id IN (SELECT media_id FROM media_tags_map WHERE tags_id = $tags_id)";
        $type_join   = "fsm.feeds_id = -1";
    }
    elsif ( $type eq 'feeds' )
    {
        $type_clause = <<EOF;
            fsm.stories_id = fsm.stories_id
            AND fsm.feeds_id IN (
                SELECT feeds_id
                FROM feeds_tags_map
                WHERE tags_id = $tags_id
EOF
        $type_join = "s.stories_id = fsm.stories_id";
    }
    else
    {
        die( "Unknown source type: $type" );
    }

    return ( $type_clause, $type_join );
}

# generate a title describing the source
sub get_encoded_source_title($)
{
    my $source = shift;

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
sub get_source_clause($;$$)
{
    my ( $source, $media_alias, $feeds_alias ) = @_;

    my $m_a = $media_alias ? "${media_alias}." : "";
    my $f_a = $feeds_alias ? "${feeds_alias}." : "";

    if ( $source->{ type } eq 'all' )
    {
        return '1 = 1';
    }
    elsif ( $source->{ type } eq 'tags' )
    {
        return <<EOF;
            (
                (
                    ( ${m_a}media_id IN
                        (
                            SELECT mtm.media_id
                            FROM media_tags_map AS mtm
                            WHERE tags_id = $source->{id}
                        )
                    ) AND ( ${f_a}feeds_id IS NULL )
                ) OR ( ${f_a}feeds_id in
                    (
                        SELECT ftm.feeds_id
                        FROM feeds_tags_map AS ftm
                        WHERE tags_id = $source->{id}
                    )
                )
            )
EOF
    }
    elsif ( $source->{ type } eq 'media' )
    {
        return "${m_a}media_id = $source->{id}";
    }
    elsif ( $source->{ type } eq 'feeds' )
    {
        return "${f_a}feeds_id = $source->{id}";
    }
    else
    {
        die( "uknown set type " . $source->{ type } );
    }
}

# TERM PAGES

# get a link to a term page
sub get_term_file($$;$)
{
    my ( $stem, $language_code, $term ) = @_;

    $_term_pages->{ $stem . ' [' . $language_code . ']' } = $term;

    $stem =~ s~/~~g;

    return "terms_${stem}_${language_code}.html";
}

# get a list of stories and sentences that match a given term
sub get_term_sentences($$$;$$)
{
    my ( $stem, $term, $language_code, $start_date, $end_date ) = @_;

    my $quoted_term_stem     = $_db->dbh->quote( $stem );
    my $quoted_language_code = $_db->dbh->quote( $language_code );

    my $query = <<EOF;
        SELECT DISTINCT s.*,
               COALESCE(m.name, f.name) AS name,
               qs.sentence_number,
               ss.sentence,
               CAST( DATE_TRUNC('day', s.publish_date) AS date ) AS time_slice
        FROM stories AS s,
             query_sentences AS qs
                LEFT JOIN feeds AS f ON (qs.feeds_id = f.feeds_id),
             story_sentence_words AS terms,
             media AS m,
             story_sentences AS ss
        WHERE s.stories_id = qs.stories_id
              AND terms.stories_id = qs.stories_id
              AND terms.stem = $quoted_term_stem
              AND terms.language = $quoted_language_code
              AND qs.sentence_number = terms.sentence_number
              AND ss.stories_id = terms.stories_id
              AND ss.sentence_number = terms.sentence_number
              AND s.media_id = m.media_id
        ORDER BY time_slice
EOF

    return $_db->query( $query )->hashes;
}

# generate html list of stories about the term
sub generate_sentences_html
{
    my ( $sentences ) = @_;

    my $html;
    my $i = 0;
    my $s = $sentences->[ 0 ];

    while ( $s )
    {
        my $time_s = $s;

        # print time
        $html .= "<p><b>$s->{time_slice}</b></p>\n<ul>\n";

        while ( $s && ( $time_s->{ time_slice } eq $s->{ time_slice } ) )
        {
            my $story_s = $s;

            # print story
            my $enc_title = encode_entities( HTML::StripPP::strip( decode( 'utf8', $s->{ title } || '' ) ) );
            my $enc_media_name = encode_entities( HTML::StripPP::strip( decode( 'utf8', $s->{ name } ) ) );

            $html .= "<li><b>$enc_media_name:</b> <a href='$s->{url}'>$enc_title</a>\n<ul>\n";

            while ( $s && ( $story_s->{ stories_id } == $s->{ stories_id } ) )
            {

                # print setence
                my $enc_sentence = encode_entities( $s->{ sentence } );
                $html .= "<li>$enc_sentence</li>\n";

                # increment $i and set $s for all enclosing loops
                $s = $sentences->[ ++$i ];
            }

            $html .= "</ul></li>\n";
        }

        $html .= "</ul>\n";
    }

    return $html;
}

# get the top num source names with the most stories in the list
sub get_top_story_source_names($$)
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
        $_time_slices = $_db->query( "SELECT DISTINCT time_slice FROM query_words ORDER BY time_slice ASC" )->flat;
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

# generate a csv of the word count and return the file name
sub generate_csv_page($$$)
{
    my ( $source, $pr_source, $words ) = @_;

    my $file = "csv_" . get_source_file( $source, $pr_source );
    $file =~ s/.html/.csv/;

    if ( !open( FILE, ">$file" ) )
    {
        die( "Unable to open file '$file': $!" );
    }

    print FILE '"stem","term","language","p"' . "\n";
    for my $word ( @{ $words } )
    {
        print FILE "\"$word->{ stem }\",\"$word->{ term }\",\"$word->{ language }\",\"$word->{ p }\"\n";
    }

    close( FILE );

    return $file;
}

# generate term page
sub generate_term_page($$$)
{
    my ( $stem, $term, $language_code ) = @_;

    print STDERR "$term [$language_code] ...\n";

    my $sentences = get_term_sentences( $stem, $term, $language_code );

    my $term_stories_chart_html = generate_term_timeline( $sentences );

    my $term_stories_html = generate_sentences_html( $sentences );

    my $enc_query = encode_entities( $_query );

    my $enc_term = encode_entities( $term );

    my $enc_language_code = encode_entities( $language_code );

    my $term_file = get_term_file( $stem, $language_code );

    my $fh = safe_file_open( "> $term_file" );

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
<h2>Media Cloud Topic Explorer: $enc_query stories about $enc_term [$enc_language_code]</h2>

<h3>Number of stories including '$enc_query' and '$enc_term [$enc_language_code]'</h3>

$term_stories_chart_html

<h3>Stories including '$enc_query' and '$enc_term [$enc_language_code]'</h3>

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
sub generate_term_pages()
{

    while ( my ( $stem, $term ) = each( %{ $_term_pages } ) )
    {
        my $language_code;

        # "stem [language_code]" => ("stem", "language_code")
        ( $stem, $language_code ) = split( / \[/, $stem );
        $language_code =~ s/\]//;
        generate_term_page( $stem, $term, $language_code );
    }

}

# SOURCE SENTENCE PAGES

# get file name of source sentences file
sub get_source_sentences_file($)
{
    my $source = shift;

    my $source_file = get_source_file( $source );

    return "sentences_$source_file";
}

# get a list of stories and sentences that match a given term
sub get_source_sentences($)
{
    my $source = shift;

    my $source_clause = get_source_clause( $source, 'm', 'f' );

    my $query = <<EOF;
        SELECT DISTINCT s.*,
                        COALESCE(m.name, f.name) AS name,
                        qs.sentence_number,
                        ss.sentence,
                        CAST( DATE_TRUNC('day', s.publish_date) AS date ) AS time_slice
        FROM stories AS s,
             query_sentences AS qs
                LEFT JOIN feeds AS f ON (qs.feeds_id = f.feeds_id),
             media AS m,
             story_sentences AS ss
        WHERE s.stories_id = qs.stories_id
              AND ss.stories_id = qs.stories_id
              AND ss.sentence_number = qs.sentence_number
              AND ($source_clause)
              AND s.media_id = m.media_id
        ORDER BY time_slice
EOF

    return $_db->query( $query )->hashes;
}

# generate term page
sub generate_source_sentences_page($)
{
    my $source = shift;

    my $enc_source_title = get_encoded_source_title( $source );

    print STDERR "$enc_source_title sentences ...\n";

    my $sentences = get_source_sentences( $source );

    my $stories_html = generate_sentences_html( $sentences );

    my $enc_query = encode_entities( $_query );

    my $enc_language_code = encode_entities( $_language_code );

    my $sentences_file = get_source_sentences_file( $source );

    my $fh = safe_file_open( "> $sentences_file" );

    $fh->print(
        qq~
<html>
<head>
<title>$enc_source_title stories about $enc_query [$enc_language_code] - Media Cloud Topic Explorer</title>
<style type="text/css">
a { color: 32588F; text-decoration: none;}
</style>
</head>
<body>
<h2>Media Cloud Topic Explorer: $enc_source_title stories about $enc_query [$enc_language_code]</h2>

<h3>Sentences in $enc_source_title including '$enc_query [$enc_language_code]'</h3>

$stories_html

<h3>Explore Other Sources</h3>

$_links_html

</body>

</html>
~
    );

    $fh->close();

    return $sentences_file;
}

# GENERATE_CHARTS

# get cached value of p for args
sub get_cached_p($$$;$$$)
{
    my ( $source, $pr_source, $num, $stem, $language_code, $group_by_time_slice ) = @_;

    my $key = Dumper( $source, $pr_source, $stem, $language_code, $group_by_time_slice );

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
sub set_cached_p($$$$;$$$)
{
    my ( $p, $source, $pr_source, $num, $stem, $language_code, $group_by_time_slice ) = @_;

    my $key = Dumper( $source, $pr_source, $stem, $language_code, $group_by_time_slice );

    my $c = $_p_cache->{ $key };

    if ( !$c || ( $c->{ num } < $num ) )
    {
        $_p_cache->{ $key }->{ num } = $num;
        $_p_cache->{ $key }->{ p }   = $p;
    }
}

# get a sql clause that restricts the terms within query words
sub get_stem_clause($$$$)
{
    my ( $stem_field, $stem, $language_field, $language_code ) = @_;

    if ( $stem )
    {
        return "$stem_field = " . $_db->{ dbh }->quote( $stem ) . " AND $language_field = " .
          $_db->{ dbh }->quote( $language_code );
    }
    else
    {
        return "1=1";
    }
}

# get the terms with the highest pr(set, pr_set)
sub get_pr($$$;$$$)
{
    my ( $source, $pr_source, $num, $stem, $language_code, $group_by_time_slice ) = @_;

    my $a_m = get_source_clause( $source );
    my $b_m = get_source_clause( $pr_source );

    my $stem_clause = get_stem_clause( 'stem', $stem, 'language', $language_code );

    my ( $time_slice_field, $a_time_slice_field, $time_slice_join, $time_slice_group ) = ( '', '', '', '' );
    my $table = 'query_words_source';
    if ( $group_by_time_slice )
    {
        $time_slice_field   = ', time_slice';
        $a_time_slice_field = ', a.time_slice';
        $time_slice_join    = 'AND a.time_slice = b.time_slice';
        $time_slice_group   = 'time_slice, ';
        $table              = 'query_words';
    }

    # exclude source a from source b only if source a does not wholly include source b
    my ( $exclude_source_from_pr ) = $_db->query( "SELECT 1 FROM query_words WHERE $b_m AND NOT $a_m LIMIT 1" )->flat;
    if ( $exclude_source_from_pr )
    {
        $b_m .= " AND NOT ( $a_m ) ";
    }

    my $pr_equation = "( ( a.p * SQRT(a.p) ) / b.p )";

    my $max_p = MAX_P;

    my $words = $_db->query(
        <<EOF
        SELECT $pr_equation AS p,
               a.term,
               a.stem,
               a.language
               $a_time_slice_field,
               a.p AS a_p,
               b.p AS b_p
        FROM
            (
                SELECT LEAST( $max_p, AVG(term_count / source_sentence_count) ) AS p,
                       MIN(term) AS term,
                       stem,
                       language
                       $time_slice_field
                FROM $table
                WHERE $a_m
                      AND $stem_clause
                GROUP BY $time_slice_group
                         stem,
                         language
                HAVING AVG(term_count) > 0
            ) AS a
                LEFT JOIN (
                    SELECT LEAST( $max_p, avg(greatest(.1, term_count) / source_sentence_count) ) AS p,
                           MIN(term) AS term,
                           stem,
                           language
                           $time_slice_field
                    FROM $table
                    WHERE $b_m
                          AND $stem_clause
                    GROUP BY $time_slice_group
                             stem,
                             language
                ) AS b ON (a.stem = b.stem AND a.language = b.language $time_slice_join)
        ORDER BY $time_slice_group
                 p DESC
                 $time_slice_field
        LIMIT $num
EOF
    )->hashes;

    set_cached_p( $words, $source, $pr_source, $num, $stem, $language_code, $group_by_time_slice );

    return $words;
}

# get p(source) if only set is passed or pr(source, pr_source) if two sources are passed
sub get_p($$$;$$$)
{
    my ( $source, $pr_source, $num, $stem, $language_code, $group_by_time_slice ) = @_;

    if ( my $p = get_cached_p( $source, $pr_source, $num, $stem, $language_code, $group_by_time_slice ) )
    {
        return $p;
    }

    if ( $pr_source )
    {
        return get_pr( $source, $pr_source, $num, $stem, $language_code, $group_by_time_slice );
    }

    my $source_clause = get_source_clause( $source );

    my $stem_clause = get_stem_clause( 'stem', $stem, 'language', $language_code );

    my $time_slice_field = '';
    my $table            = 'query_words_source';
    if ( $group_by_time_slice )
    {
        $time_slice_field = ', time_slice';
        $table            = 'query_words';
    }

    my $max_p = MAX_P;

    my $words = $_db->query(
        <<EOF
        SELECT LEAST( $max_p, AVG(term_count / source_sentence_count) ) AS p,
               stem,
               MIN(term) AS term,
               language
               $time_slice_field
        FROM $table
        WHERE $source_clause
              AND $stem_clause
        GROUP BY stem,
                 language
                 $time_slice_field
        HAVING AVG(term_count) > 0
        ORDER BY p DESC
                 $time_slice_field
        LIMIT $num
EOF
    )->hashes;

    set_cached_p( $words, $source, $pr_source, $num, $stem, $language_code, $group_by_time_slice );

    return $words;

}

# generate a word cloud for p(source) or pr(source, pr_source)
sub generate_p_cloud($$)
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
        my $url = get_term_file( $word->{ stem }, $word->{ language }, $word->{ term } );

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

        $cloud->add( $t, $url, List::Util::max( $word->{ p } * 1000000, 1 ) );

        # my $label = join('/', map { sprintf("%.04f", $word->{$_}) } grep { $word->{$_} } qw(p a_p b_p));
        # $cloud->add("$t [$label]", $url, List::Util::max($word->{p} * 1000000, 1));

    }
    my $chart_html = $cloud->html( NUM_CLOUD_TERMS );

    my $sentences_html = "";

    if ( !$pr_source )
    {
        my $esc_sentences_file = URI::Escape::uri_escape( generate_source_sentences_page( $source ) );
        $sentences_html = "<div align='center'><a href='$esc_sentences_file'>[view all sentences]</a></div>\n";
    }

    my $esc_csv_file = URI::Escape::uri_escape( generate_csv_page( $source, $pr_source, $words ) );
    my $csv_html = "<div align='center'><a href='$esc_csv_file'>[download word count csv]</a></div>\n";

    my $html = qq~
<div id="word_cloud">
$chart_html
$sentences_html
$csv_html
</div>
~;

    return $html;
}

# get lookup table for google chart simple encoding values
# http://code.google.com/apis/chart/formats.html#simple
sub get_google_chart_simple_encoding_lookup()
{
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
sub generate_timeline_chart_url($$$)
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
        push( @{ $days }, $time_slices->[ $#{ $time_slices } ] );
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

    #print STDERR "google chart url: $url\n";

    return $url;
}

# generate timeline of top ten most prevalent terms every time_slice over the entire timespan
sub generate_p_timeline($$)
{
    my ( $source, $pr_source ) = @_;

    my $words = get_p( $source, $pr_source, NUM_TIMELINE_TERMS );

    if ( !$_time_slices )
    {
        $_time_slices = $_db->query( "SELECT DISTINCT time_slice FROM query_words ORDER BY time_slice ASC" )->flat;
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
                    $count = int( 100 * $time_slice_count->{ p } );
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
sub generate_p_charts($;$)
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
sub get_source_file($)
{
    my $source = shift;

    my $name = join( '_', $source->{ type }, $source->{ id }, $source->{ name } ) . ".html";

    $name =~ s~/~~g;

    return $name;
}

# get file for pr comparison of two sources
sub get_pr_file($$)
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
sub generate_pr_link($$)
{
    my ( $source, $pr_source ) = @_;

    my $file = get_pr_file( $source, $pr_source );

    return "<a href='" . uri_escape( $file ) . "'>" . get_encoded_source_title( $pr_source ) . "</a>";
}

# PRINT PAGES

# print the page with header and footer
sub print_page($$$;$)
{
    my ( $file, $title, $charts, $pr_links ) = @_;

    my $fh = safe_file_open( "> $file" );

    my $charts_html = join( "\n", map { "<div id='chart_set'>$_</div>" } @{ $charts } );

    $fh->print(
        qq~
<html>
<head>
<title>${_query} [${_language_code}] stories in $title - Media Cloud Topic Explorer</title>
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
<h2>Media Cloud Topic Explorer: ${_query} [${_language_code}] stories in $title </h2>

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
sub generate_pr_page($$$)
{
    my ( $source, $pr_source, $pr_links ) = @_;

    my $pr = generate_p_charts( $source,    $pr_source );
    my $rp = generate_p_charts( $pr_source, $source );

    my $file = get_pr_file( $source, $pr_source );

    my $title = get_encoded_source_title( $source ) . " v. " . get_encoded_source_title( $pr_source );

    print_page( $file, $title, [ $pr, $rp ], $pr_links );
}

# generate a page for a source (feed/media/tag)
sub generate_source_page($$)
{
    my ( $source, $pr_sources ) = @_;

    print STDERR get_encoded_source_title( $source ) . " ...\n";

    my $p = generate_p_charts( $source );
    my $pr = generate_p_charts( $source, { type => 'all' } );

    my $prs      = [];
    my $pr_links = [];

    $pr_sources =
      [ grep { !( ( $_->{ type } eq $source->{ type } ) && ( $_->{ id } eq $source->{ id } ) ) } @{ $pr_sources } ];

    for my $pr_source ( @{ $pr_sources } )
    {
        push( @{ $pr_links }, generate_pr_link( $source, $pr_source ) );
    }

    for my $pr_source ( @{ $pr_sources } )
    {
        generate_pr_page( $source, $pr_source, $pr_links );
    }

    my $file = get_source_file( $source );

    print_page( $file, get_encoded_source_title( $source ), [ $p, $pr ], [ @{ $pr_links } ] );
}

# generate index page with summary p and links to all source pages
sub generate_index_page()
{
    print STDERR "index ...\n";

    my $source = { type => 'all' };

    my $p_all = generate_p_charts( $source );

    print_page( "index.html", get_encoded_source_title( $source ), [ $p_all ] );
}

# insert list of stories_id that match query
sub insert_query_sentences($$$$$$$)
{
    my ( $term_table, $type, $type_tags_id, $query, $language_code, $start_date, $end_date ) = @_;

    #my ($type_clause, $type_join) = get_story_where_and_join($type, $type_tags_id);
    #my ($type_clause, $type_join) = ('1=1', '0=1');
    my $stem = get_stem( $query, $language_code );

    $_db->query(
        <<EOF,
        INSERT INTO query_sentences (
            stories_id,
            sentence_number,
            media_id,
            feeds_id,
            time_slice
        )
            SELECT DISTINCT stories_id,
                            sentence_number,
                            media_id,
                            null::int,
                            CAST(DATE_TRUNC('day', publish_date) AS date) AS time_slice
            FROM story_sentence_words
            WHERE DATE_TRUNC('day', publish_date) >= date '$start_date'
                  AND DATE_TRUNC('day', publish_date) <= date '$end_date'
                  AND stem = LOWER(?)
                  AND language = ?
                  AND media_id IN (
                    SELECT media_id
                    FROM media_tags_map
                    WHERE tags_id = $type_tags_id
                  )
EOF
        $stem, $language_code
    );
    $_db->query( "ANALYZE query_sentences" );
}

# return the query that inserts rows into the query_words table.
# if table is 'media', include stories in a media with a word_cloud:${tag_name} tag and group by media id.
# if table is 'feeds', include stories in a feed with the word_cloud:${tag_name} tag and group by feed id.
sub insert_query_words($$$$$$$)
{
    my ( $term_table, $type, $type_tags_id, $query, $language_code, $start_date, $end_date ) = @_;

    insert_query_sentences( $term_table, $type, $type_tags_id, $query, $language_code, $start_date, $end_date );

    my $stem = get_stem( $query, $language_code );

    $_db->query(
        <<EOF,
        INSERT INTO query_words (
            term,
            stem,
            language,
            term_count,
            source_sentence_count,
            media_id,
            feeds_id,
            time_slice
        )
            SELECT DISTINCT MIN(sw.term) AS term,
                            sw.stem,
                            sw.language,
                            COUNT(sw.stem_count) AS term_count,
                            ?::numeric AS source_sentence_count,
                            qs.media_id,
                            qs.feeds_id,
                            qs.time_slice
            FROM query_sentences AS qs,
                 story_sentence_words AS sw
            WHERE qs.stories_id = sw.stories_id
                  AND qs.sentence_number = sw.sentence_number
                  AND sw.stem <> ?
                  AND sw.language <> ?
            GROUP BY qs.media_id,
                     qs.feeds_id,
                     time_slice,
                     sw.stem,
                     sw.language
EOF
        MIN_SOURCE_SENTENCES, $stem, $language_code
    );
}

# aggregate query words into source totals.
#
# each source will have 0 entries for all words that are not present in the source
# to make avg(term_count / aggregate_sentence_count) work for sets of sources
# (otherwise, the avg will only inlucde sentence counts for sources with non-zero entries for a given term).
sub create_query_words_source_table
{
    $_db->query(
        <<EOF
        CREATE TEMPORARY TABLE all_query_words AS
            SELECT stem,
                   MIN(term) AS term,
                   language
            FROM query_words
            GROUP BY stem
EOF
    );
    $_db->query(
        <<EOF
        CREATE TEMPORARY TABLE all_query_sources AS
            SELECT media_id,
                   feeds_id
            FROM query_words
            GROUP BY media_id,
                     feeds_id
EOF
    );

    $_db->query(
        <<EOF,
        CREATE TEMPORARY TABLE query_words_source AS
            SELECT term,
                   stem,
                   language,
                   0::numeric AS term_count,
                   ?::numeric AS source_sentence_count,
                   media_id,
                   feeds_id
            FROM all_query_words,
                 all_query_sources
EOF
        MIN_SOURCE_SENTENCES
    );

    $_db->query(
        <<EOF
        UPDATE query_words_source AS qws
        SET term_count = q.sum_term_count
        FROM (
            SELECT SUM(term_count) AS sum_term_count,
                   media_id,
                   feeds_id,
                   stem
            FROM query_words
            GROUP BY media_id,
                     feeds_id,
                     stem,
                     language
        ) AS q
        WHERE qws.media_id = q.media_id
              AND COALESCE(-1, qws.feeds_id) = COALESCE(-1, q.feeds_id)
              AND qws.stem = q.stem
              AND qws.language = q.language
EOF
    );

    $_db->query(
        <<EOF,
        UPDATE query_words_source AS qw
        SET source_sentence_count = q.sum_sentence_count
        FROM (
            SELECT qs.media_id,
                   qs.feeds_id,
                   GREATEST(
                       ?,
                       COUNT(DISTINCT qs.stories_id::text || 'Z' || qs.sentence_number::text)
                   ) AS sum_sentence_count
            FROM query_sentences AS qs
            GROUP BY qs.media_id,
                     qs.feeds_id
        ) AS q
        WHERE qw.media_id = q.media_id
              AND COALESCE(-1, qw.feeds_id) = COALESCE(-1, q.feeds_id)
EOF
        MIN_SOURCE_SENTENCES
    );

    $_db->query( "CREATE INDEX query_words_agg_mfs ON query_words_source(media_id, feeds_id, stem, language)" );
    $_db->query( "CREATE INDEX query_words_agg_ms ON query_words_source(media_id, stem, language)" );
    $_db->query( "ANALYZE query_words_source" );
}

# generate a temporary table to hold the word counts for stories that match the query by media_id and time_slice
# this intermediate table is used to generate all of the p and pr counts above
sub generate_query_words_table($$$$$$)
{
    my ( $term_table, $source_tags_id, $query, $language_code, $start_date, $end_date ) = @_;

    my $query_words = split( /\s+/, $query );

    if ( !$query )
    {
        die( "no query" );
    }

    $_db->query(
        <<EOF
        CREATE TEMPORARY TABLE query_sentences (
            stories_id INT,
            sentence_number INT,
            media_id INT,
            feeds_id INT,
            time_slice TIMESTAMP
        )
EOF
    );
    $_db->query(
        <<EOF
        CREATE TEMPORARY TABLE query_words (
            term TEXT,
            stem TEXT,
            language TEXT,
            term_count NUMERIC,
            source_sentence_count NUMERIC,
            media_id INT,
            feeds_id INT,
            time_slice DATE
        )
EOF
    );

    # $_db->query("truncate table query_words");
    # eval {
    #     $_db->query("DROP INDEX query_words_mw");
    #     $_db->query("DROP INDEX query_words_t");
    # };

    insert_query_words( $term_table, 'media', $source_tags_id, $query, $language_code, $start_date, $end_date );

    # insert_query_words($term_table, 'feeds', $source_tags_id, $query, $language_code, $start_date, $end_date);

    $_db->query( "CREATE INDEX query_words_mfs ON query_words(media_id, feeds_id, stem, language)" );
    $_db->query( "CREATE INDEX query_words_ms ON query_words(media_id, stem, language)" );
    $_db->query( "ANALYZE query_words" );

    $_db->query(
        <<EOF,
        UPDATE query_words AS qw
        SET source_sentence_count = q.sum_sentence_count
        FROM (
            SELECT qs.media_id,
                   qs.feeds_id,
                   GREATEST(
                       ?,
                       COUNT(DISTINCT qs.stories_id::text || 'Z' || qs.sentence_number::text)
                   ) AS sum_sentence_count
            FROM query_sentences AS qs
            GROUP BY qs.media_id,
                     qs.feeds_id
        ) AS q
        WHERE qw.media_id = q.media_id
              AND COALESCE(-1, qw.feeds_id) = COALESCE(-1, q.feeds_id)
EOF
        MIN_SOURCE_SENTENCES
    );

    create_query_words_source_table();
}

# generate a report for the given query
sub generate_report($$$$$$$$)
{
    my ( $topic_dir, $term_table, $source_tags_id, $set_tags, $query, $language_code, $start_date, $end_date ) = @_;

    reset_caches();

    if ( !( -d $topic_dir ) && !mkdir( $topic_dir ) )
    {
        die( "Unable to make directory '$topic_dir': $!" );
    }

    chdir( $topic_dir );

    $source_tags_id ||= get_tag( 'word_cloud', 'default' )->{ tags_id };
    $set_tags ||= 'media_type:blogs media_type:newspapers';

    generate_query_words_table( $term_table, $source_tags_id, $query, $language_code, $start_date, $end_date );

    my $media_sources = get_sources( 'media', $source_tags_id );
    my $feeds_sources = get_sources( 'feeds', $source_tags_id );
    my $set_sources   = get_sources( 'tags',  $set_tags );

    my $sources = [ @{ $set_sources }, sort { $a->{ name } cmp $b->{ name } } ( @{ $media_sources }, @{ $feeds_sources } ) ];

    $_query         = $query;
    $_language_code = $language_code;

    $_links_html = generate_links( $sources );

    generate_index_page();

    for my $source ( @{ $sources } )
    {
        generate_source_page( $source, $set_sources );
    }

    generate_term_pages();
}

# (re)connect to db
sub reconnect_to_db()
{
    $_db = MediaWords::DB::connect_to_db();
}

# start a polling daemon, generating reports from word_cloud_topics as they appear in the db
sub generate_reports_from_db($$)
{
    my ( $base_directory, $base_url ) = @_;

    while ( 1 )
    {
        reconnect_to_db();

        my $topics =
          $_db->query( "SELECT * FROM word_cloud_topics WHERE state = 'pending' ORDER BY word_cloud_topics_id" )->hashes;
        for my $topic ( @{ $topics } )
        {
            $_db->query( "UPDATE word_cloud_topics SET state = 'generating' WHERE word_cloud_topics_id = ?",
                $topic->{ word_cloud_topics_id } );

            my $topic_dir = "$base_directory/" . $topic->{ word_cloud_topics_id };

            generate_report(
                $topic_dir,
                'story_' . $topic->{ type },
                $topic->{ source_tags_id },
                $topic->{ set_tag_names },
                $topic->{ query },
                $topic->{ language },
                $topic->{ start_date },
                $topic->{ end_date }
            );

            my $topic_url = "$base_url/" . $topic->{ word_cloud_topics_id };
            $_db->query( "UPDATE word_cloud_topics SET state = 'completed', url = ? WHERE word_cloud_topics_id = ?",
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
        generate_reports_from_db( $ARGV[ 0 ], $ARGV[ 1 ] );
    }
    elsif ( @ARGV == 8 )
    {
        reconnect_to_db();
        generate_report( $ARGV[ 0 ], $ARGV[ 1 ], $ARGV[ 2 ], $ARGV[ 3 ], $ARGV[ 4 ], $ARGV[ 5 ], $ARGV[ 6 ], $ARGV[ 7 ] );
    }
    else
    {
        print( "usage: $0 <directory> ( ( <url> ) | ( " .
              "<term_type> <source_tags_id> <set_tags> <query> <language_code> <start_date> <end_date> ) )\n" );
        exit 1;
    }
}

main();
