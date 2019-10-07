package MediaWords::TM::Snapshot::GEXF;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::TM::Snapshot::ExtraFields;
use MediaWords::Util::Colors;

use Date::Format;
use Readonly;
use XML::Simple;

import_python_module( __PACKAGE__, 'webapp.tm.snapshot.gexf' );


# max number of media to include in gexf map
Readonly my $MAX_GEXF_MEDIA => 500;

# max and mind node sizes for gexf snapshot
Readonly my $MAX_NODE_SIZE => 20;
Readonly my $MIN_NODE_SIZE => 2;

# only layout the gexf export if there are fewer than this number of sources in the graph
Readonly my $MAX_LAYOUT_SOURCES => 2000;


# get a description for the gexf file export
sub _get_gexf_description($$)
{
    my ( $db, $timespan ) = @_;

    my $topic = $db->query( <<SQL, $timespan->{ snapshots_id } )->hash;
select * from topics t join snapshots s using ( topics_id ) where snapshots_id = ?
SQL

    my $description = <<END;
Media Cloud topic map of $topic->{ name } for $timespan->{ period } timespan
from $timespan->{ start_date } to $timespan->{ end_date }
END

    if ( $timespan->{ foci_id } )
    {
        my $focus = $db->require_by_id( 'foci', $timespan->{ foci_id } );
        $description .= "for $focus->{ name } focus";
    }

    return $description;
}

# return only the $edges that are within the giant component of the network
sub _trim_to_giant_component($)
{
    my ( $edges ) = @_;

    my $edge_pairs = [ map { [ $_->{ source }, $_->{ target } ] } @{ $edges } ];

    my $trimmed_edges = py_giant_component( $edge_pairs );

    my $edge_lookup = {};
    map { $edge_lookup->{ $_->[ 0 ] }->{ $_->[ 1 ] } = 1 } @{ $trimmed_edges };

    my $links = [ grep { $edge_lookup->{ $_->{ source } }->{ $_->{ target } } } @{ $edges } ];

    DEBUG( "_trim_to_giant_component: " . scalar( @{ $edges } ) . " -> " . scalar( @{ $links } ) );

    return $links;
}

sub _get_weighted_edges
{
    my ( $db, $media, $options ) = @_;

    my $max_media            = $options->{ max_media };
    my $include_weights      = $options->{ include_weights } || 0;
    my $max_links_per_medium = $options->{ max_links_per_medium } || 1_000_000;

    DEBUG(<<"EOF"
_get_weighted_edges:
    * $max_media max media;
    * $include_weights include_weights;
    * $max_links_per_medium max_links_per_medium
EOF
    );

    my $media_links = $db->query( <<SQL,

        WITH top_media AS (
            SELECT *
            FROM snapshot_medium_link_counts
            ORDER BY media_inlink_count DESC
            LIMIT \$1
        ),

        ranked_media AS (
            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY source_media_id
                    ORDER BY
                        l.link_count DESC,
                        rlc.inlink_count DESC
                ) AS source_rank
            FROM snapshot_medium_links AS l
                JOIN top_media AS slc
                    ON l.source_media_id = slc.media_id
                JOIN top_media AS rlc
                    ON l.ref_media_id = rlc.media_id
        )

        SELECT *
        FROM ranked_media
        WHERE source_rank <= \$2

SQL
        $max_media, $max_links_per_medium
    )->hashes;

    my $media_map = {};
    map { $media_map->{ $_->{ media_id } } = 1 } @{ $media };

    my $edges = [];
    my $k     = 0;
    for my $media_link ( @{ $media_links } )
    {
        next unless ( $media_map->{ $media_link->{ source_media_id } } && $media_map->{ $media_link->{ ref_media_id } } );
        my $edge = {
            id     => $k++,
            source => $media_link->{ source_media_id },
            target => $media_link->{ ref_media_id },
            weight => ( $include_weights ? $media_link->{ link_count } : 1 )
        };

        push( @{ $edges }, $edge );
    }

    $edges = _trim_to_giant_component( $edges );

    return $edges;
}

# given an rgb hex string, return a hash in the form { r => 12, g => 0, b => 255 }, which is
# what we need for the viz:color element of the gexf snapshot
sub _get_color_hash_from_hex
{
    my ( $rgb_hex ) = @_;

    return {
        r => hex( substr( $rgb_hex, 0, 2 ) ),
        g => hex( substr( $rgb_hex, 2, 2 ) ),
        b => hex( substr( $rgb_hex, 4, 2 ) )
    };
}

# get a consistent color from MediaWords::Util::Colors.  convert to a color hash as needed by gexf.  translate
# the set to a topic specific color set value for get_consistent_color.
sub _get_color
{
    my ( $db, $timespan, $set, $id ) = @_;

    my $color_set;
    if ( grep { $_ eq $set } qw(partisan_code media_type partisan_retweet) )
    {
        $color_set = $set;
    }
    else
    {
        $color_set = "topic_${set}_$timespan->{ snapshot }->{ topics_id }";
    }

    $id ||= 'none';

    my $color = MediaWords::Util::Colors::get_consistent_color( $db, $color_set, $id );

    return _get_color_hash_from_hex( $color );
}

# scale the nodes such that the biggest node size is $MAX_NODE_SIZE and the smallest is $MIN_NODE_SIZE
sub _scale_node_sizes
{
    my ( $nodes ) = @_;

    map { $_->{ 'viz:size' }->{ value } += 1 } @{ $nodes };

    my $max_size = 1;
    for my $node ( @{ $nodes } )
    {
        my $s = $node->{ 'viz:size' }->{ value };
        $max_size = $s if ( $max_size < $s );
    }

    my $scale = $MAX_NODE_SIZE / $max_size;

    for my $node ( @{ $nodes } )
    {
        my $s = $node->{ 'viz:size' }->{ value };

        $s = int( $scale * $s );

        $s = $MIN_NODE_SIZE if ( $s < $MIN_NODE_SIZE );

        $node->{ 'viz:size' }->{ value } = $s;
    }
}

# call webapp.tm.snapshot.graph_layout.layout_gexf
sub _layout_gexf($)
{
    my ( $gexf ) = @_;

    my $nodes = $gexf->{ graph }->[ 0 ]->{ nodes }->{ node };

    my $layout;

    if ( scalar( @{ $nodes } ) < $MAX_LAYOUT_SOURCES )
    {
        DEBUG( "laying out grap with " . scalar( @{ $nodes } ) . " sources ..." );
        my $xml = XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' );

        $layout = py_layout_gexf( $xml );
    }
    else
    {
        WARN( "refusing to layout graph with more than $MAX_LAYOUT_SOURCES sources" );
        $layout = {};
    }

    for my $node ( @{ $nodes } )
    {
        my $pos = $layout->{ $node->{ id } };
        my ( $x, $y ) = $pos ? @{ $pos } : ( 0, 0 );
        $node->{ 'viz:position' }->{ x } = $x;
        $node->{ 'viz:position' }->{ y } = $y;
    }
}

# Get a gexf snapshot of the graph described by the linked media sources within
# the given topic timespan.
#
# Layout the graph using the gaphviz neato algorithm.
#
# Accepts these $options:
#
# * color_field - color the nodes by the given field: $medium->{ $color_field }
#   (default 'media_type').
# * max_media -  include only the $max_media media sources with the most
#   inlinks in the timespan (default 500).
# * include_weights - if true, use weighted edges
# * max_links_per_medium - if set, only include the top $max_links_per_media
#   out links from each medium, sorted by medium_link_counts.link_count and
#   then inlink_count of the target medium
# * exclude_media_ids - list of media_ids to exclude
sub get_gexf_snapshot
{
    my ( $db, $timespan, $options ) = @_;

    $options->{ max_media }   ||= $MAX_GEXF_MEDIA;
    $options->{ color_field } ||= 'media_type';

    my $exclude_media_ids_list = join( ',', map { int( $_ ) } ( @{ $options->{ exclude_media_ids } }, 0 ) );

    my $media = $db->query( <<END, $options->{ max_media } )->hashes;
select distinct
        m.*,
        mlc.media_inlink_count inlink_count,
        mlc.story_count,
        mlc.facebook_share_count,
        mlc.post_count
    from snapshot_media_with_types m
        join snapshot_medium_link_counts mlc using ( media_id )
    where
        m.media_id not in ( $exclude_media_ids_list )
    order
        by mlc.media_inlink_count desc
    limit ?
END

    MediaWords::TM::Snapshot::ExtraFields::add_extra_fields_to_snapshot_media( $db, $timespan, $media );

    my $gexf = {
        'xmlns'              => "http://www.gexf.net/1.2draft",
        'xmlns:xsi'          => "http://www.w3.org/2001/XMLSchema-instance",
        'xmlns:viz'          => "http://www.gexf.net/1.1draft/viz",
        'xsi:schemaLocation' => "http://www.gexf.net/1.2draft http://www.gexf.net/1.2draft/gexf.xsd",
        'version'            => "1.2",
    };

    my $meta = { 'lastmodifieddate' => Date::Format::time2str( '%Y-%m-%d', time ) };
    push( @{ $gexf->{ meta } }, $meta );

    push( @{ $meta->{ creator } }, 'Berkman Center' );

    my $description = _get_gexf_description( $db, $timespan );
    push( @{ $meta->{ description } }, $description );

    my $graph = {
        'mode'            => "static",
        'defaultedgetype' => "directed",
    };
    push( @{ $gexf->{ graph } }, $graph );

    my $attributes = { class => 'node', mode => 'static' };
    push( @{ $graph->{ attributes } }, $attributes );

    my $i = 0;
    my $attribute_types = $MediaWords::TM::Snapshot::ExtraFields::MEDIA_STATIC_GEXF_ATTRIBUTE_TYPES;
    while ( my ( $name, $type ) = each( %{ $attribute_types } ) )
    {
        push( @{ $attributes->{ attribute } }, { id => $i++, title => $name, type => $type } );
    }

    my $edges = _get_weighted_edges( $db, $media, $options );
    $graph->{ edges }->{ edge } = $edges;

    my $edge_lookup;
    map { $edge_lookup->{ $_->{ source } } = 1; $edge_lookup->{ $_->{ target } } = 1; } @{ $edges };

    my $total_link_count = 1;
    map { $total_link_count += $_->{ inlink_count } } @{ $media };

    for my $medium ( @{ $media } )
    {
        next unless ( $edge_lookup->{ $medium->{ media_id } } );

        my $node = {
            id    => $medium->{ media_id },
            label => $medium->{ name },
        };

        # FIXME should this be configurable?
        $medium->{ view_medium } = 'https://sources.mediacloud.org/#/sources/' . $medium->{ media_id };

        my $j = 0;
        while ( my ( $name, $type ) = each( %{ $attribute_types } ) )
        {
            my $value = $medium->{ $name };
            if ( !defined( $value ) )
            {
                $value = ( $type eq 'integer' ) ? 0 : '';
            }

            push( @{ $node->{ attvalues }->{ attvalue } }, { for => $j++, value => $value } );
        }

        my $color_field = $options->{ color_field };
        $node->{ 'viz:color' } = [ _get_color( $db, $timespan, $color_field, $medium->{ $color_field } ) ];
        $node->{ 'viz:size' } = { value => $medium->{ inlink_count } + 1 };

        push( @{ $graph->{ nodes }->{ node } }, $node );
    }

    _scale_node_sizes( $graph->{ nodes }->{ node } );

    _layout_gexf( $gexf );

    my $xml = XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' );

    return $xml;
}

1;
