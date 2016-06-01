package MediaWords::CM::Graph::Attribute::Metric;

=pod

=head1 NAME

Mediawords::CM::Graph::Attribute::Metric - a metric attribute attached to a node in a controversy graph

=head1 SYNOPSIS

    use MediaWords::CM::Graph::Node::Attribute::Metric;

    my $node = MediaWords::CM::Graph::Node->new( id 1, label => 'foo' );

    $node->add_attribute( MediaWords::CM::Graph::Attribute::Tag->new( name => 'inlink count', value => 57 );

=head1 DESCRIPTION

MediaWords::CM::Graph::Attribute represents a metric attribute attached to a node in a controversy graph.

Metric attributes must be numbers.

=cut

use strict;
use warnings;

use Moose;

extends 'MediaWords::CM::Graph::Attribute';

use Modern::Perl '2015';
use MediaWords::CommonLibs;

has 'value' => ( is => 'ro', isa => 'Num', required => 1 );

no Moose;
__PACKAGE__->meta->make_immutable;

1;
