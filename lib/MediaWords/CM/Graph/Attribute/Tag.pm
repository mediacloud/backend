package MediaWords::CM::Graph::Attribute::Tag;

=pod

=head1 NAME

Mediawords::CM::Graph::Attribute::Tag - a tag attribute attached to a node in a controversy graph

=head1 SYNOPSIS

    use MediaWords::CM::Graph::Node::Attribute::Tag;

    my $node = MediaWords::CM::Graph::Node->new( id 1, label => 'foo' );

    $node->add_attribute( MediaWords::CM::Graph::Attribute::Tag->new( name => 'bar', value => 'baz' );
    $node->add_attribute( MediaWords::CM::Graph::Attribute::Tag->new( name => 'bat', value => 'bam' );

=head1 DESCRIPTION

MediaWords::CM::Graph::Attribute represents a tag attribute attached to a node in a controversy graph.

Tag attributes are those with low cardinality.

=cut

use strict;
use warnings;

use Moose;

extends 'MediaWords::CM::Graph::Attribute';

use Modern::Perl '2015';
use MediaWords::CommonLibs;

no Moose;
__PACKAGE__->meta->make_immutable;

1;
