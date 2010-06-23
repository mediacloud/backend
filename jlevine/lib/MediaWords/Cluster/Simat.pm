package MediaWords::Cluster::Simat;

# Adapted from Text::SenseClusters::simat.pl
# http://search.cpan.org/~tpederse/Text-SenseClusters/Toolkit/matrix/simat.pl

###### ORIGINAL AUTHORS ###########
#
#  Amruta Purandare, University of Pittsburgh
#
#  Ted Pedersen, University of Minnesota, Duluth
#  tpederse at d.umn.edu
#
##### ORIGINAL COPYRIGHT ##############
#
# Copyright (c) 2002-2008, Amruta Purandare and Ted Pedersen
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to:
#
#  The Free Software Foundation, Inc.,
#  59 Temple Place - Suite 330,
#  Boston, MA  02111-1307, USA.

use strict;
use Data::Dumper;
use Math::SparseVector;

sub get_sparse_cosine_matrix
{
    my ( $sparse_mat ) = @_;
    
    my @sparse_vectors;
    my $rows = scalar @{ $sparse_mat };
    
    for my $vector ( @{ $sparse_mat } )
    {
        my $sparse_vec = Math::SparseVector->new;
        
        # Turn each "sparse vector" into a real sparse vector
        for ( my $i = 0; $i < scalar @{ $vector } - 1; $i += 2 ) {
            $sparse_vec->set( $vector->[$i], $vector->[$i + 1] );
        }
        
        unless ( $sparse_vec->isnull ) { 
            $sparse_vec->normalize;
        }
        
        push @sparse_vectors, $sparse_vec;
    }
    
    my $cosines = {};

    # finding cosines
    for my $i ( 1 .. $rows )
    {   
        for my $j ( $i + 1 .. $rows )
        {
            my $dp = $sparse_vectors[ $i - 1 ]->dot( $sparse_vectors[ $j - 1 ] );
            $cosines->{ $i }->{ $j } = $dp if $dp != 0;
        }
    }
    
    return $cosines;
}

1;
