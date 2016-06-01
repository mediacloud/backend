package MediaWords::CM::Graph::Attribute;

=pod

=head1 NAME

Mediawords::CM::Graph::Attribute - an attribute attached to a node in a controversy graph

=head1 SYNOPSIS

    use MediaWords::CM::Graph::Node::Attribute;

    my $node = MediaWords::CM::Graph::Node->new( id 1, label => 'foo' );

    $node->add_attribute( MediaWords::CM::Graph::Attribute->new( name => 'bar', value => 'baz' );
    $node->add_attribute( MediaWords::CM::Graph::Attribute->new( name => 'bat', value => 'bam' );

=head1 DESCRIPTION

MediaWords::CM::Graph::Attribute represents an attribute attached to a node in a controversy graph.  Every attribute
consists of a name, a value, and a type associated with the particular Attribute class.  This class represents
generic attributes.

Attributes that can be considered tags, with low cardinality, should use the
MediaWords::CM::Graph::Attribute::Tag class.  Numeric metrics that can be used for comparing nodes should use the
MediaWords::CM::Graph::Attribute::Metric class.


=cut

use strict;
use warnings;

use Moose;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

=head1 ATTRIBUTES

=head2 name

Unique id for the attribute for the given node

=cut

has 'name' => ( is => 'ro', isa => 'Str', required => 1 );

=head2 value

Value for the attribute.  Can be any scalar.

=cut

has 'value' => ( is => 'ro', isa => 'Str', required => 1 );

=head2 type

Returns 'Generic Attribute'.

=cut

has 'type' => ( is => 'ro', isa => 'Str', required => 1, default => 'Generic Attribute', init_arg => undef );

no Moose;
__PACKAGE__->meta->make_immutable;

1;
