package MediaWords::Util::BigPDLVector;

# Jon's wrapper for PDL vector methods--should use the same interface as SparseHashVector, SparseSlowVector
#
# Sparse vectors are now PDL objects and should be really small and fast.
#
# Eventually I should settle on an interface for everything, perhaps with object orientation?
#   I'd also need to provide constructor methods and things like that....

use strict;
use PDL;
use PDL::Reduce;

# Export some of these methods....
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw( vector_new vector_add vector_dot vector_div vector_norm
  vector_normalize vector_length vector_nnz vector_get vector_set vector_string );

sub vector_new
{
    my ( $length ) = @_;
    return ( zeroes $length);
}

# adds 2 sparse vectors
sub vector_add
{
    my ( $v1, $v2 ) = @_;
    return $v1 + $v2;
}

# take the dot product of two vectors
sub vector_dot
{
    my ( $v1, $v2 ) = @_;
    my $cos = inner( $v1, $v2 );    # inner product
    return $cos->sclr();            # converts PDL object to Perl scalar
}

# divides each vector entry by a given divisor
sub vector_div
{
    my ( $v, $divisor ) = @_;
    return $v / $divisor;
}

# Returns the norm of a vector
sub vector_norm
{
    my ( $v ) = @_;

    # TODO: A real norm operation...
    return $v->reduce( '+' );    # lol, not even close...
}

# normalizes given sparse vector
sub vector_normalize
{
    return norm( $_[ 0 ] );
}

# returns the length of the vector
sub vector_length
{
    my ( $v ) = @_;
    my @dims = dims $v ;
    return $dims[ 0 ];
}

# returns an array containing the non-zero values of the vector
sub vector_nnz
{
    my ( $v ) = @_;
    my @piddle_list = which( $v )->list();
    return \@piddle_list;
}

# get a specified value from a vector
sub vector_get
{
    my ( $v, $pos ) = @_;
    return index( $v, $pos )->sclr();
}

# Set a value $val at position $pos in vector $v
sub vector_set
{
    my ( $v, $pos, $val ) = @_;
    index( $v, $pos ) .= $val if $val > 0;
    return $v;
}

sub vector_string
{
    my ( $v ) = @_;
    my $string = '';

    for my $pos ( @{ vector_nnz $v } )
    {
        my $val = vector_get $v, $pos;
        $string .= "$pos: $val\n";
    }

    return $string;
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

# Returns 1 if vector is null, otherwise 0
sub isnull { }

1;
