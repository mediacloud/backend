package MediaWords::CM::Graph::Node;

=pod

=head1 NAME

Mediawords::CM::Graph::Node - a node in a controversy graph

=head1 SYNOPSIS

    use MediaWords::CM::Graph::Node;

    my $g = MediaWords::CM::Graph->new( db => $db, controversy_dump_time_slices_id => $cdts_id );

    $g->add_node( MediaWords::CM::Graph::Node->new( id => 1, label => 'foo' ) );
    $g->add_node( MediaWords::CM::Graph::Node->new( id => 2, label => 'bar' ) );


=head1 DESCRIPTION

MediaWords::CM::Graph::Node represents a node within a MediaWords::CM::Graph.  This class describes a generic,
minimal node. Most nodes will belong to a subclass of this class, such as MediaWords::CM::Graph::Node::Medium or
MediaWords::CM::Graph::Word.

=cut

use strict;
use warnings;

use Moose;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use MediaWords::CM::Graph::Attribute;
use MediaWords::CM::Graph::Attribute::Tag;
use MediaWords::CM::Graph::Attribute::Metric;

=head1 ATTRIBUTES

=head2 id

Unique id for the node for the given graph and node type.

=cut

has 'id' => ( is => 'ro', isa => 'Str', required => 1 );

=head2 label

Human readable label for the node.  Should be unique for the graph and node type.

=cut

has 'label' => ( is => 'ro', isa => 'Str', required => 1 );

=head2 type

Returns 'Generic Node'.

=cut

has 'type' => ( is => 'ro', isa => 'Str', required => 1, default => 'Generic Node', init_arg => undef );

=head2 attributes

Return a list of MediaWords::Graph::Node::Attribute objects associated with the given node.

=head2 add_attribute

Add a MediaWords::Graph::Node::Attribute object to the node.

=cut

has 'attributes' => (
    is       => 'ro',
    isa      => 'ArrayRef[MediaWords::CM::Graph::Attribute]',
    default  => sub { [] },
    init_arg => undef
);

=head get_attribute( $name )

Return the attribute with the given name, or undef if no such attribute exists for this node.

=cut

sub get_attribute($$)
{
    my ( $self, $name ) = @_;

    map { return $_ if ( $_->name eq $name ) } @{ $self->attributes };

    return undef;
}

=head2 add_attribute

Add a MediaWords::Graph::Node::Attribute object to the node.

=cut

sub add_attribute($$)
{
    my ( $self, $attribute ) = @_;

    TRACE( sub { "add_attribute: " . $attribute->name . " " . $attribute->value } );

    LOGDIE( "attribute '" . $attribute->name . "' already exists" ) if ( $self->get_attribute( $attribute->name ) );

    push( @{ $self->attributes }, $attribute );
}

=head2 add_tag_attribute( $name, $value )

Add a new tag attribute to the node with the given name and value.

=cut

sub add_tag_attribute($$$)
{
    my ( $self, $name, $value ) = @_;

    $self->add_attribute( MediaWords::CM::Graph::Attribute::Tag->new( name => $name, value => $value ) );
}

=head2 add_metric_attribute( $name, $value )

Add a new metric attribute to the node with the given name and value.

=cut

sub add_metric_attribute($$$)
{
    my ( $self, $name, $value ) = @_;

    $self->add_attribute( MediaWords::CM::Graph::Attribute::Metric->new( name => $name, value => $value ) );
}

=head2 layout

Return a hash of values that can be used to describe the layout of the node within the graph.

=cut

has 'layout' => ( is => 'ro', isa => 'HashRef', default => sub { {} }, init_arg => undef );

=head2 type_id

Returns $node->type . ' [' . $node->id . ']'

=cut

sub type_id
{
    my ( $self ) = @_;

    return $self->type . ' [' . $self->id . ']';
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
