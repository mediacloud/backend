package MediaWords::CM::Graph::Edge;

=pod

=head1 NAME

Mediawords::CM::Graph::Edge - an edge in a controversy graph

=head1 SYNOPSIS

    use MediaWords::CM::Graph;
    use MediaWords::CM::Graph::Edge;

    my $g = MediaWords::CM::Graph->new( db => $db, controversy_dump_time_slices_id => $cdts_id );

    $g->add_node( MediaWords::CM::Graph::Node->new( id => 1, label => 'foo' ) );
    $g->add_node( MediaWords::CM::Graph::Node->new( id => 2, label => 'bar' ) );

    my $node_a = $g->get_node( type => 'MediaWords::CM::Graph::Node', id => 1 );
    my $node_b = $g->get_node( type => 'MediaWords::CM::Graph::Node', id => 2 );
    $g->add_edge( MediaWords::CM::Graph::Edge->new( source => $node_a, target => $node_b, weight => $link_count ) );

=head1 DESCRIPTION

MediaWords::CM::Graph::Edge represents an edge within a MediaWords::CM::Graph.  This class describes a generic,
minimal edge. Most edges will belong to a subclass of this class, such as MediaWords::CM::Graph::Edge::Hyperlink.

=cut

use strict;
use warnings;

use Moose;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

=head1 ATTRIBUTES

=head2 source

Edge source node.

=cut

has 'source' => ( is => 'ro', isa => 'MediaWords::CM::Graph::Node', required => 1 );

=head2 target

Edge target node.

=cut

has 'target' => ( is => 'ro', isa => 'MediaWords::CM::Graph::Node', required => 1 );

=head2 weight

Edge weight.

=cut

has 'weight' => ( is => 'ro', isa => 'Num', required => 1 );

=head2 type

Returns 'Generic Edge'.

=cut

has 'type' => ( is => 'ro', isa => 'Str', required => 1, default => 'Generic Edge', init_arg => undef );

no Moose;
__PACKAGE__->meta->make_immutable;

1;
