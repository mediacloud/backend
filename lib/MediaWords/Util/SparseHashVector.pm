package MediaWords::Util::SparseVector;
use MediaWords::CommonLibs;

# Jon's rewrite of Math::SparseVector
#
# Instead of object orientation, I've just provided a bunch of declarative
#   functions that might be handy to use with sparse vectors.
#
# Sparse vectors are just hashes, with their keys being the non-zero values, eg:
# {
#     3 => 6.342
#     7 => 27.342
#    29 => 0.321
# }

use strict;

# Export some of these methods....
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw( vector_add vector_dot vector_div vector_norm vector_normalize );

# adds 2 sparse vectors
sub vector_add
{
    my ( $v1, $v2 ) = @_;
    my $sum = $v1;    # Copy the first vector into the sum?

    while ( my ( $key, $val ) = each %{ $v2 } )
    {
        $sum->{ $key } += $val;
    }

    return $sum;
}

# take the dot product of two vectors
sub vector_dot
{
    my ( $v1, $v2 ) = @_;
    my $dotprod = 0;

    while ( my ( $key, $val1 ) = each %{ $v1 } )
    {
        my $val2 = $v2->{ $key };
        $dotprod += $val1 * $val2 if defined $val2;
    }

    return $dotprod;
}

# divides each vector entry by a given divisor
sub vector_div
{
    my ( $v, $divisor ) = @_;

    for my $key ( keys %{ $v } )
    {
        $v->{ $key } /= $divisor;
    }

    return $v;
}

# Returns the norm of a vector
sub vector_norm
{
    my ( $v ) = @_;
    return 0 unless defined $v;

    my $sum = 0;

    for my $val ( values %{ $v } )
    {
        $sum += $val**2;
    }

    return sqrt $sum;
}

# normalizes given sparse vector
sub vector_normalize
{

    # my ( $v ) = @_;
    return vector_div( $_[ 0 ], vector_norm( $_[ 0 ] ) );
}

############ POTENTIALLY USEFUL FUNCTIONS ###################
# Maybe not....

# prints sparse vector
sub print { }

# returns the equivalent string form
sub stringify { }

# increments value at given index
sub incr { }

############### USELESS FUNCTIONS ####################
# Nothing to do for any of these--do them your damn self!

# sparse vector contructor - creates an empty sparse vector
sub new { }

# sets value at given index
sub set { }

# returns value at given index
sub get { }

# Returns 1 if vector is null, otherwise 0
sub isnull { }

# returns indices of non-zero values in sorted order
sub keys { }

1;
