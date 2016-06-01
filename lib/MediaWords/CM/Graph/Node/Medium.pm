package MediaWords::CM::Graph::Node::Medium;

=pod

=head1 NAME

Mediawords::CM::Graph::Node::Medium - a node in a controversy graph representing a media source

=head1 SYNOPSIS

    use MediaWords::CM::Graph::Node::Medium;

    my $g = MediaWords::CM::Graph->new( db => $db, controversy_dump_time_slices_id => $cdts_id );

    $g->add_node( MediaWords::CM::Graph::Node->new( medium => $medium_a );
    $g->add_node( MediaWords::CM::Graph::Node->new( medium => $medium_b );


=head1 DESCRIPTION

Mediawords::CM::Graph::Node::Medium represents a media source with a MediaWords::CM::Graph.  It is a subclass of
MediaWords::CM::Graph::Node.

The constructor for the object is a $medium hash.  The class sets the id and label attributes based on the
media_id and name of the media source.

=cut

use strict;
use warnings;

use Moose;

extends 'MediaWords::CM::Graph::Node';

use Modern::Perl '2015';
use MediaWords::CommonLibs;

=head1 ATTRIBUTES

=head2 id

Unique id for the node for the given graph and node type.  This is automatically set to the media_id of the
$medium passed into the constructor.

=cut

has 'id' => ( is => 'ro', isa => 'Int', init_arg => undef, lazy => 1, default => sub { $_[ 0 ]->medium->{ media_id } } );

=head2 label

Human readable label for the.  This is automatically set to the name of the $medium passed into the constructor.

=cut

has 'label' => ( is => 'ro', isa => 'Str', init_arg => undef, lazy => 1, default => sub { $_[ 0 ]->medium->{ name } } );

=head2 type

Returns 'Media Source'.

=cut

has 'type' => ( is => 'ro', required => 1, default => 'Media Source', init_arg => undef );

=head2 medium

The $medium passed into the constructor.

=cut

has 'medium' => ( is => 'ro', isa => 'HashRef', required => 1 );

no Moose;
__PACKAGE__->meta->make_immutable;

1;
