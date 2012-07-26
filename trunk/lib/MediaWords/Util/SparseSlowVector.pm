package MediaWords::Util::SparseSlowVector;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use 5.006;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration    use Math::SparseVector ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.

our %EXPORT_TAGS = (
    'all' => [
        qw(

          )
    ]
);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{ 'all' } } );

our @EXPORT = qw(

);

our $VERSION = '0.04';

use overload
  '++'       => 'incr',
  '+'        => 'add',
  'fallback' => undef;

# sparse vector contructor
# creates an empty sparse vector
sub new
{

    # my $class = shift;
    my $self = {};
    bless( $self, $_[ 0 ] );
    return $self;
}

# sets value at given index
sub set
{

    # my ( $self, $key, $value ) = @_;
    # my $self = shift;
    # my $key = shift;
    # my $value = shift;

    if ( !defined $_[ 1 ] || !defined $_[ 2 ] )
    {
        print STDERR "Usage: vector->set(key,value)\n";
        exit;
    }
    if ( $_[ 2 ] == 0 )
    {
        print STDERR "Can not store 0 in the Math::SparseVector.\n";
        exit;
    }
    $_[ 0 ]->{ $_[ 1 ] } = $_[ 2 ];
}

# returns value at given index
sub get
{

    # my ( $self, $key ) = @_;
    # my $self = shift;
    # my $key = shift;

    if ( !defined $_[ 1 ] )
    {
        print STDERR "Usage: vector->get(key)\n";
        exit;
    }
    if ( defined $_[ 0 ]->{ $_[ 1 ] } )
    {
        return $_[ 0 ]->{ $_[ 1 ] };
    }
    return 0;
}

# returns indices of non-zero values in sorted order
sub keys
{

    # my $self = shift;
    my @indices = keys %{ $_[ 0 ] };
    my @sorted = sort { $a <=> $b } @indices;
    return @sorted;
}

# returns 1 if the vector is empty
sub isnull
{

    # my $self = shift;
    my @indices = $_[ 0 ]->keys;
    if ( scalar( @indices ) == 0 )
    {
        return 1;
    }
    return 0;
}

# prints sparse vector
sub print
{
    my $self = shift;
    foreach my $ind ( $self->keys )
    {
        print "$ind " . $self->get( $ind ) . " ";
    }
    print "\n";
}

# returns the equivalent string form
sub stringify
{
    my $self = shift;
    my $str  = "";
    foreach my $ind ( $self->keys )
    {
        $str .= "$ind " . $self->get( $ind ) . " ";
    }
    chop $str;
    return $str;
}

# increments value at given index
sub incr
{
    my $self = shift;
    my $key  = shift;
    if ( !defined $key )
    {
        print STDERR "Usage: vector->incr(key)\n";
        exit;
    }
    $self->{ $key }++;
}

# adds 2 sparse vectors
sub add
{

    # my ( $self, $v2 ) = @_;
    # my $self = shift;
    # my $v2 = shift;

    if ( !defined $_[ 1 ] )
    {
        print STDERR "Usage: v1->add(v2)\n";
        exit;
    }
    foreach my $key ( $_[ 1 ]->keys )
    {
        if ( defined $_[ 0 ]->{ $key } )
        {
            $_[ 0 ]->{ $key } += $_[ 1 ]->get( $key );
        }
        else
        {
            $_[ 0 ]->{ $key } = $_[ 1 ]->get( $key );
        }
    }
}

# returns the norm
sub norm
{

    # my $self = shift;
    my $sum = 0;
    foreach my $key ( $_[ 0 ]->keys )
    {
        my $value = $_[ 0 ]->{ $key };
        $sum += $value**2;
    }
    return sqrt $sum;
}

# normalizes given sparse vector
sub normalize
{

    # my $self = shift;
    my $vnorm = $_[ 0 ]->norm;
    if ( $vnorm != 0 )
    {
        $_[ 0 ]->div( $vnorm );
    }
}

sub dot
{

    # my ( $self, $v2 ) = @_;
    # my $self = shift;
    # my $v2 = shift;

    if ( !defined $_[ 1 ] )
    {
        print STDERR "Usage: v1->dot(v2)\n";
        exit;
    }
    my $dotprod = 0;

    # optimize to do lesser comparisons by looping on
    # the smaller vector
    if ( scalar( $_[ 1 ]->keys ) < scalar( $_[ 0 ]->keys ) )
    {

        # v2 is smaller
        foreach my $key ( $_[ 1 ]->keys )
        {
            if ( defined $_[ 0 ]->{ $key } )
            {
                $dotprod += $_[ 1 ]->get( $key ) * $_[ 0 ]->{ $key };
            }
        }
    }
    else
    {

        # self is smaller or equal to v2
        foreach my $key ( $_[ 0 ]->keys )
        {
            if ( defined $_[ 1 ]->{ $key } )
            {
                $dotprod += $_[ 1 ]->get( $key ) * $_[ 0 ]->{ $key };
            }
        }
    }

    return $dotprod;
}

# divides each vector entry by a given divisor
sub div
{
    my $self    = shift;
    my $divisor = shift;
    if ( !defined $divisor )
    {
        print STDERR "Usage: v1->div(DIVISOR)\n";
        exit;
    }
    if ( $divisor == 0 )
    {
        print STDERR "Divisor 0 not allowed in Math::SparseVector::div().\n";
        exit;
    }
    foreach my $key ( $self->keys )
    {
        $self->{ $key } /= $divisor;
    }
}

# adds a given sparse vector to a binary sparse vector
sub binadd
{
    my $v1 = shift;
    my $v2 = shift;

    if ( !defined $v2 )
    {
        print STDERR "Usage: v1->binadd(v2)\n";
        exit;
    }

    foreach my $key ( $v2->keys )
    {
        $v1->{ $key } = 1;
    }
}

# deallocates all the vector entries
sub free
{
    my $self = shift;
    %{ $self } = ();
    undef %{ $self };
}

1;
__END__

=head1 NAME

Math::SparseVector - Supports sparse vector operations such as 
setting a value in a vector, reading a value at a given index,
obtaining all indices, addition and dot product of two sparse vectors, 
and vector normalization. 

=head1 MODULE HISTORY

This module is the successor to Sparse::Vector, which was re-cast 
into this new namespace in order to introduce another module 
Math::SparseMatrix, which makes use of this module. 

=head1 SYNOPSIS

  use Math::SparseVector;

  # creating an empty sparse vector object
  $spvec=Math::SparseVector->new;

  # sets the value at index 12 to 5
  $spvec->set(12,5);

  # returns value at index 12
  $value = $spvec->get(12);

  # returns the indices of non-zero values in sorted order
  @indices = $spvec->keys;

  # returns 1 if the vector is empty and has no keys
  if($spvec->isnull) {
    print "vector is null.\n";
  }
  else  {
    print "vector is not null.\n";
  }

  # print sparse vector to stdout
  $spvec->print;

  # returns the string form of sparse vector
  # same as print except the string is returned
  # rather than displaying on stdout
  $spvec->stringify;

  # adds sparse vectors v1, v2 and stores 
  # result into v1
  $v1->add($v2);

  # adds binary equivalent of v2 to v1
  $v1->binadd($v2);
  # binary equivalnet treats all non-zero values 
  # as 1s

  # increments the value at index 12
  $spvec->incr(12);

  # divides each vector entry by a given divisor 4
  $spvec->div(4);

  # returns norm of the vector
  $spvec_norm = $spvec->norm;

  # normalizes a sparse vector
  $spvec->normalize;

  # returns dot product of the 2 vectors
  $dotprod = $v1->dot($v2);

  # deallocates all entries
  $spvec->free;

=head1 USAGE NOTES

=over 

=item 1. Loading Math::SparseVector Module

To use this module, you must insert the following line in your Perl program
before using any of the supported methods.

    use Math::SparseVector;

=item 2. Creating a Math::SparseVector Object

The following line creates a new object of Math::SparseVector class referred 
with the name 'spvec'.

    $spvec=Math::SparseVector->new;

The newly created 'spvec' vector will be initially empty.

=item 3. Using Methods

Now you can use any of the following methods on this 'spvec' Math::SparseVector
object.

=over

=item 1. set(i,n) - Sets the value at index i to n
     
         # equivalent to $spvec{12}=5;
         $spvec->set(12,5); 

=item 2. get(i)    - Returns the value at index i
        
         # equivalent to $value=$spvec{12};
         $value = $spvec->get(12); 

=item 3. keys()    - Returns the indices of all non-zero values in the vector

         # equivalent to @keys=sort {$a <=> $b} keys %spvec;
         @indices = $spvec->keys;

=item 4. isnull()  - Returns 1 if the vector is empty and has no keys

         # similar to
         # if(scalar(keys %spvec)==0) {print "vector is null.\n";}
         if($spvec->isnull) { print "vector is null.\n"; }

=item 5. print()   - Prints the sparse vector to stdout - Output will show a list of space separated 'index value' pairs for each non-zero 'value' in the vector.

         # similar to
         # foreach $ind (sort {$a<=>$b} keys %spvec)
             # { print "$ind " . $spvec{$ind} . " "; }
         $spvec->print;

=item 6. stringify() - Returns the vector in a string form. Same as print() method except the vector is written to a string that is returned instead of displaying onto stdout

         # the below will do exactly same as $spvec->print;
         $string=$spvec->stringify;
         print "$string\n";

=item 7. v1->add(v2) - Adds contents of v2 to vector v1. 

         Similar to v1+=v2

         $v1->add($v2);
         If v1 = (2,  , , 5, 8, ,  , , 1)
         &  v2 = ( , 1, , 3,  , , 5, , 9)
         where blanks show the 0 values that are not stored in 
         Math::SparseVector.

         After      $v1->add($v2); 
         v1 = (2, 1, , 8, 8, , 5, , 10) and v2 remains same

=item 8. v1->binadd(v2) - Binary equivalent of v2 is added into v1. Binary equivalent of a vector is obtained by setting all non-zero values to 1s.

         If v1 = (1,  , , 1, 1, ,  , , 1)
         &  v2 = ( , 1, , 1,  , , 1, , 1)
         Then, after v1->binadd(v2),
         v1 will be (1, 1, , 1, 1, , 1, , 1).

         If v1 = (1,  , , 1, 1, ,  , , 1)
         &  v2 = ( , 1, , 3,  , , 5, , 9)
         v1->binadd(v2);
         will set v1 to (1, 1, , 1, 1, , 1, , 1).

=item 9. incr(i)   - Increments the value at index i

         # is similar to $spvec{12}++;
         $spvec->incr(12);

=item 10. div(n)   - Divides each vector entry by a given divisor n

         $spvec->div(4);
         If spvec = (2,  , , 5, 8, ,  , , 1)
         Then, $spvec->div(4)
         will set spvec to (0.5, , , 1.25, 2, , , , 0.25)

=item 11. norm()   - Returns the norm of a given vector

         $spvec_norm = $spvec->norm;
         If spvec = (2,  , , 5, 8, ,  , , 1)
         $spvec->norm will return the value 
         = sqrt(2^2 + 5^2 + 8^2 + 1)
         = sqrt(4 + 25 + 64 + 1)
         = 9.69536

=item 12. v1->dot(v2) - Returns the dot product of two vectors

         $dotprod = $v1->dot($v2);
         If v1 = (2,  , , 5, 8, ,  , , 1)
                 &  v2 = ( , 1, , 3,  , , 5, , 9)
         v1->dot(v2) returns
         5*3 + 1*9 = 15 + 9 = 24

=item 13. free()   - Deallocates all entries and makes the vector empty

         $spvec->free;
         will set spvec to null vector ()

=back
=back

=head1 AUTHORS

Amruta Purandare, University of Pittsburgh
amruta at cs.pitt.edu

Ted Pedersen, University of Minnesota, Duluth
tpederse at d.umn.edu

Mahesh Joshi, Carnegie-Mellon University
maheshj at cmu.edu

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2006-2008, Amruta Purandare, Ted Pedersen, Mahesh Joshi

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to

 The Free Software Foundation, Inc.,
 59 Temple Place - Suite 330,
 Boston, MA  02111-1307, USA.

=cut
