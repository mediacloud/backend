package MediaWords::CM::Graph::Edge::Hyperlink;

=pod

=head1 NAME

Mediawords::CM::Graph::Edge::Hyperlink - an edge in a controversy graph representing a hyperlink between media sources

=head1 SYNOPSIS

    use MediaWords::CM::Graph;
    use MediaWords::CM::Graph::Edge::HyperLink;

    my $g = MediaWords::CM::Graph->new( db => $db, controversy_dump_time_slices_id => $cdts_id );

    $g->add_node( MediaWords::CM::Graph::Node::Medium->new( medium => $media_id_a ) );
    $g->add_node( MediaWords::CM::Graph::Node::Medium->new( medium => $media_id_b ) );

    my $node_a = $g->get_node( type => 'MediaWords::CM::Graph::Node::Medium', id => $media_id_a );
    my $node_b = $g->get_node( type => 'MediaWords::CM::Graph::Node::Medium', id => $media_id_b );
    $g->add_edge( MediaWords::CM::Graph::Edge::Hyperlink->new( source => $node_a, target => $node_b, weight => $link_count ) );

=head1 DESCRIPTION

MediaWords::CM::Graph::Edge::Hyperlink acts as n edge representing a hyperlink between two
MediaWords::CM::Graph::Node::Medium nodes.

=cut

use strict;
use warnings;

use Moose;

extends 'MediaWords::CM::Graph::Edge';

use Modern::Perl '2015';
use MediaWords::CommonLibs;

=head1 ATTRIBUTES

=head2 source

Edge source node.  Must be a MediaWords::CM::Graph::Node::Medium object.

=cut

has 'source' => ( is => 'ro', isa => 'MediaWords::CM::Graph::Node::Medium', required => 1 );

=head2 target

Edge target node.  Must be a MediaWords::CM::Graph::Node::Medium object.

=cut

has 'target' => ( is => 'ro', isa => 'MediaWords::CM::Graph::Node::Medium', required => 1 );

=head2 type

Returns 'Hyperlink'.

=cut

has 'type' => ( is => 'ro', isa => 'Str', required => 1, default => 'Hyperlink', init_arg => undef );

no Moose;
__PACKAGE__->meta->make_immutable;

1;
