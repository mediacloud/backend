package MediaWords::CM::Graph;

=pod

=head1 NAME

Mediawords::CM::Graph - graph object for exporting controversy related networks

=head1 SYNOPSIS

    use MediaWords::CM::Graph;

    my $g = MediaWords::CM::Graph->new( db => $db, controversy_dump_time_slices_id => $cdts_id );

    # add media as nodes, links as edges, layout, and export the gexf
    $g->add_media_nodes_with_hyperlink_edges();
    $g->layout( 'media type' );

    my $gexf = $g->export_gexf();

    # alternatively, manipulate the Nodes, Edges, and Attributes individually

    $g->add_node( MediaWords::CM::Graph::Node::Medium->new( medium => $medium_a ) );
    $g->add_node( MediaWords::CM::Graph::Node::Medium->new( medium => $medium_b ) );

    my $node_a = $g->get_node( type => 'MediaWords::CM::Graph::Node::Medium', id => $medium_a->{ media_id } );
    my $node_b = $g->get_node( type => 'MediaWords::CM::Graph::Node::Medium', id => $medium_b->{ media_id } );
    $g->add_edge( MediaWords::CM::Graph::Edge::Hyperlink->new( source => $node_a, target => $node_b, weight => $link_count ) );


=head1 DESCRIPTION

MediaWords::CM::Graph allows the user to create a graph that describes network relationships within a controversy.
The graph can be manipulated to generate network statistics, can be laid out into a map, and can be exported
into a text format for use by an external application.

A Graph consists of Nodes and Edges.  Nodes have Attributes, which are data associated with each Node that should be
exported along with the graph structure.

Nodes, Edges, and Attributes have subclasses that provide type information and also support for Media Cloud specific
operations relevant to those types.  Each Node can be either a Medium or a Word.  An Edge can be either a Hyperlink,
a Content Similarity, or a Content Cooccurence.  An Attribute can be either a Tag or a Metric.

=cut

use strict;
use warnings;

use Moose;

use Readonly;
use Scalar::Util;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use MediaWords::CM::Dump;
use MediaWords::CM::Graph::Attribute;
use MediaWords::CM::Graph::Edge;
use MediaWords::CM::Graph::Edge::Hyperlink;
use MediaWords::CM::Graph::Node;
use MediaWords::CM::Graph::Node::Medium;

Readonly my $MAX_NODE_SIZE => 20;
Readonly my $MIN_NODE_SIZE => 2;

=head1 ATTRIBUTES

=head2 db
=cut

has 'db' => ( is => 'ro', isa => 'DBIx::Simple::MediaWords', required => 1 );

=head2 cdts_id
=cut

has 'cdts_id' => ( is => 'ro', isa => 'Int', required => 1 );

=head2 nodes

Return list of all nodes in the graph.

=cut

has 'nodes' => ( is => 'ro', isa => 'ArrayRef[MediaWords::CM::Graph::Node]', default => sub { [] }, init_arg => undef );

=head2 edges

Return the list of all edges in the graph.

=cut

has 'edges' => (
    is       => 'ro',
    isa      => 'ArrayRef[MediaWords::CM::Graph::Edge]',
    default  => sub { [] },
    init_arg => undef,
    traits   => [ 'Array' ],
    handles  => { add_edge => 'push' },
);

=head1 METHODS

=head2 get_node( $node_type, $node_id )

Return the node with the specified $node_type and $node_id, or undef if no such node exists.

=cut

sub get_node($$$)
{
    my ( $self, $node_type, $node_id ) = @_;

    TRACE( sub { "get_node: $node_type $node_id" } );

    for my $node ( @{ $self->nodes } )
    {
        return $node if ( ( $node->type eq $node_type ) && ( $node->id eq $node_id ) );
    }

    return undef;
}

=head2 add_node( $node )

Add the node to the graph.  The node type and id must be unique within the graph.

=cut

sub add_node($$)
{
    my ( $self, $node ) = @_;

    LOGDIE( "node must be a MediaWords::CM::Graph::Node" )
      unless ( Scalar::Util::blessed( $node ) && $node->isa( 'MediaWords::CM::Graph::Node' ) );

    LOGDIE( "node already exists in graph: " . $node->type_id ) if ( $self->get_node( $node->type, $node->id ) );

    TRACE( sub { "add node: " . $node->type_id } );

    push( @{ $self->nodes }, $node );
}

=head2 add_controversy_media

Add the top 500 controversy media by inlinks to the graph as Media Source nodes.

For each node, add the following Tag attributes: media type, partisanship.

For each node, add the following Metric attributes: inlink count, outlink count, story count, bitly click count.

=cut

sub add_media_nodes_with_hyperlink_edges
{
    my ( $self ) = @_;

    my $cdts = $self->db->find_by_id( 'controversy_dump_time_slices', $self->cdts_id );

    MediaWords::CM::Dump::setup_temporary_dump_tables( $self->db, $cdts );

    # return top 500 media by inlink_count, with media type and partisan affiliation if any.  include only the
    # top 500 media that share a link with at least one other top 500 media source.
    my $media = $self->db->query( <<SQL, 500 )->hashes;
with top_media as (
    select distinct
            m.*,
            mlc.inlink_count, mlc.outlink_count, mlc.story_count, mlc.bitly_click_count,
            coalesce( dt.tag, 'none' ) partisanship
        from dump_media_with_types m
            join dump_medium_link_counts mlc on ( m.media_id = mlc.media_id )
            left join
                ( dump_media_tags_map dmtm
                    join dump_tags dt on ( dmtm.tags_id = dt.tags_id and dt.tag like 'partisan_2012_%' )
                    join dump_tag_sets dts on ( dts.tag_sets_id = dt.tag_sets_id and dts.name = 'collection' )
                ) on dmtm.media_id = m.media_id
        order by mlc.inlink_count desc
        limit ?
),

linked_top_media_ids as (
    select source_media_id media_id from dump_medium_links where ref_media_id in ( select media_id from top_media )
    union
    select ref_media_id media_id from dump_medium_links where source_media_id in ( select media_id from top_media )
)

select * from top_media m where m.media_id in ( select media_id from linked_top_media_ids )
SQL

    TRACE( sub { "add_media_nodes_with_hyperlink_edges: " . scalar( @{ $media } ) . " media" } );

    return unless ( @{ $media } );

    for my $medium ( @{ $media } )
    {
        my $node = MediaWords::CM::Graph::Node::Medium->new( medium => $medium );

        $node->add_tag_attribute( 'media type',   $medium->{ media_type } );
        $node->add_tag_attribute( 'partisanship', $medium->{ partisanship } );

        $node->add_metric_attribute( 'inlink count',      $medium->{ inlink_count } );
        $node->add_metric_attribute( 'outlink count',     $medium->{ outlink_count } );
        $node->add_metric_attribute( 'story count',       $medium->{ story_count } );
        $node->add_metric_attribute( 'bitly click count', $medium->{ bitly_click_count } );

        $self->add_node( $node );
    }

    $self->_add_media_hyperlink_edges( $media );

    MediaWords::CM::Dump::discard_temp_tables( $self->db );
}

# add an edge for every link between every media within the current dump.  assumes setup_temporary_dump_tables are
# available
sub _add_media_hyperlink_edges
{
    my ( $self, $media ) = @_;

    my $ids_table = $self->db->get_temporary_ids_table( [ map { $_->{ media_id } } @{ $media } ] );

    my $media_links = $self->db->query( <<SQL )->hashes;
select *
    from dump_medium_links
    where
        source_media_id in ( select id from $ids_table ) and
        ref_media_id in ( select id from $ids_table )
SQL

    for my $media_link ( @{ $media_links } )
    {
        TRACE( sub { "add hyperlink: $media_link->{ source_media_id } -> $media_link->{ ref_media_id }" } );
        my $source_node = $self->get_node( 'Media Source', $media_link->{ source_media_id } );
        my $target_node = $self->get_node( 'Media Source', $media_link->{ ref_media_id } );
        my $edge        = MediaWords::CM::Graph::Edge::Hyperlink->new(
            source => $source_node,
            target => $target_node,
            weight => $media_link->{ link_count }
        );

        $self->add_edge( $edge );
    }
}

=head2 export_gexf

Return a gexf string representing the graph.

=cut

sub export_gexf
{
    my ( $self, $description ) = @_;

    my $gexf = {
        'xmlns'              => "http://www.gexf.net/1.2draft",
        'xmlns:xsi'          => "http://www.w3.org/2001/XMLSchema-instance",
        'xmlns:viz'          => "http://www.gexf.net/1.1draft/viz",
        'xsi:schemaLocation' => "http://www.gexf.net/1.2draft http://www.gexf.net/1.2draft/gexf.xsd",
        'version'            => "1.2"
    };

    my $meta = { 'lastmodifieddate' => Date::Format::time2str( '%Y-%m-%d', time ) };

    push( @{ $gexf->{ meta } }, $meta );

    push( @{ $meta->{ creator } },     'Media Cloud - http://mediacloud.org' );
    push( @{ $meta->{ description } }, $description );

    my $graph = {
        'mode'            => "static",
        'defaultedgetype' => "directed",
    };
    push( @{ $gexf->{ graph } }, $graph );

    my $attributes = { class => 'node', mode => 'static' };
    push( @{ $graph->{ attributes } }, $attributes );

    my $k = 0;
    for my $edge ( @{ $self->edges } )
    {
        my $gexf_edge = { id => $k++, source => $edge->source->id, target => $edge->target->id, weight => 1 };
        push( @{ $graph->{ edges }->{ edge } }, $gexf_edge );
    }

    my $attribute_lookup = {};

    for my $node ( @{ $self->nodes } )
    {
        my $gexf_node = { id => $node->id, label => $node->label };

    # my $view_url = "[_mc_base_url_]/admin/cm/medium/$medium->{ media_id }?cdts=$cdts->{ controversy_dump_time_slices_id }";

        for my $attribute ( @{ $node->attributes } )
        {
            $attribute_lookup->{ $attribute->name } //= scalar( keys( %{ $attribute_lookup } ) );
            my $attribute_id = $attribute_lookup->{ $attribute->name };

            my $gexf_attribute = { for => $attribute_id, value => $attribute->value };

            push( @{ $gexf_node->{ attvalues }->{ attvalue } }, $gexf_attribute );
        }

        $gexf_node->{ 'viz:color' }    = { r => $node->layout->{ r }, g => $node->layout->{ g }, b => $node->layout->{ b } };
        $gexf_node->{ 'viz:size' }     = $node->layout->{ size };
        $gexf_node->{ 'viz:position' } = { x => $node->layout->{ x }, y => $node->layout->{ y } };

        push( @{ $graph->{ nodes }->{ node } }, $gexf_node );
    }

    while ( my ( $name, $id ) = each( %{ $attribute_lookup } ) )
    {
        # TODO - float for metric attributes
        push( @{ $attributes->{ attribute } }, { id => $id, title => $name, type => 'string' } );
    }

    return XML::Simple::XMLout( $gexf, XMLDecl => 1, RootName => 'gexf' );
}

# get a consistent color from MediaWords::Util::Colors.  convert to a color hash as needed by gexf.  translate
# the set to a controversy specific color set value for get_consistent_color.
sub _get_color_hash
{
    my ( $self, $node, $attribute_name ) = @_;

    my $attribute = $node->get_attribute( $attribute_name );

    my $color_set = $attribute->name;
    my $id        = $attribute->value;

    my $db = $self->db;

    $id ||= 'none';

    my $color = MediaWords::Util::Colors::get_consistent_color( $db, $color_set, $id );

    return {
        r => hex( substr( $color, 0, 2 ) ),
        g => hex( substr( $color, 2, 2 ) ),
        b => hex( substr( $color, 4, 2 ) )
    };
}

# scale the vertices such that the biggest vertex size is $MAX_VERTEX_SIZE and the smallest is $MIN_VERTEX_SIZE
sub _scale_node_sizes
{
    my ( $self ) = @_;

    my $max_size = List::Util::max( map { $_->layout->{ size } } @{ $self->nodes } );

    my $scale = $MAX_NODE_SIZE / $max_size;

    for my $node ( @{ $self->nodes } )
    {
        $node->layout->{ size } = int( $scale * $node->layout->{ size } );
        $node->layout->{ size } = List::Util::max( $node->layout->{ size }, $MIN_NODE_SIZE );
    }
}

# call graphviz to layout position of nodes
sub _layout_with_graphviz
{
    my ( $self ) = @_;

    my $nodes = $self->nodes;
    my $edges = $self->edges;

    my $graph_size       = 800;
    my $graph_attributes = {
        driver => 'neato',
        height => $graph_size,
        width  => $graph_size,
        format => 'plain'
    };

    my $gv = GraphViz2->new( global => $graph_attributes );

    my $gv_lookup   = {};
    my $node_lookup = {};
    for my $node ( @{ $nodes } )
    {
        my $i = scalar( keys( %{ $gv_lookup } ) );
        $gv_lookup->{ $node->type_id } = $i;
        $node_lookup->{ $i } = $node;
        $gv->add_node( name => $i );
    }

    for my $edge ( @{ $edges } )
    {
        $gv->add_edge( from => $gv_lookup->{ $edge->source->type_id }, to => $gv_lookup->{ $edge->target->type_id } );
    }

    $gv->run;
    my $output = $gv->dot_output;

    while ( $output =~ /node (\d+) (-?\d+\.\d+) (-?\d+\.\d+)/g )
    {
        my ( $gv_id, $x, $y ) = ( $1, $2, $3 );

        my $node = $node_lookup->{ $gv_id };

        TRACE( "layout: $gv_id " . $node->id . " $x $y" );

        $node->layout->{ x } = $x;
        $node->layout->{ y } = $y;
    }

    #$self->_scale_layout();
}

=head2 layout( $color_attribute_name )

Given an existing graph, add the following fields to the layout hash: r, g, b, size, x, y.

Use the $color_attribute as the name of the attribute with which to determine colors for the nodes.

Eventually, I think the sizing and coloring will be handled by the client side tool.

The layout is currently done by the graphviz neato algorithm.

=cut

sub layout($$)
{
    my ( $self, $color_attribute_name ) = @_;

    for my $node ( @{ $self->nodes } )
    {
        my $color_hash = $self->_get_color_hash( $node, $color_attribute_name );
        $node->layout->{ r } = $color_hash->{ r };
        $node->layout->{ g } = $color_hash->{ g };
        $node->layout->{ b } = $color_hash->{ b };

        my $inlink_attribute = $node->get_attribute( 'inlink count' );

        $node->layout->{ size } = $inlink_attribute ? $inlink_attribute->value + 1 : 1;
    }

    $self->_scale_node_sizes();

    $self->_layout_with_graphviz();

}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
