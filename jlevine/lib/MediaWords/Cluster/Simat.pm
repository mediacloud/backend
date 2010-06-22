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

######################## NOT YET STRICT!! #############################
# use strict;

# loading PDL modules
use PDL;
use PDL::NiceSlice;
use PDL::Primitive;
use PDL::IO::FastRaw;

# loading Math::SparseVector module
use Math::SparseVector;

sub get_sparse_cosine_matrix
{

    # output format
    my $format;
    if ( defined $opt_format )
    {

        # only floating point format allowed
        if ( $opt_format =~ /^f(\d+)\.(\d+)$/ )
        {
            $format = "%$1\.$2f";
        }
        else
        {
            print STDERR "ERROR($0):
            Wrong format value --format=$opt_format.\n";
            exit;
        }
    }

    # default is f16.10
    else
    {
        $format = "%16.10f";
    }

    #                       ================================
    #                          INITIALIZATION AND INPUT
    #                       ================================

    if ( !defined $_[ 0 ] )
    {
        print STDERR "ERROR($0):
            Please specify the Vector file ...\n";
        die;
    }

    # accept the vector file name
    my $infile = $_[ 0 ];

    open( IN, $infile ) || die "Error($0):
            Error(code=$!) in opening Vector file <$infile>.\n";

    #			=======================================
    #			     Finding Pair-wise Similarities
    #			=======================================

    my $line_num = 1;

    # reading first line
    $_ = <IN>;
    if ( /keyfile/ )
    {

        # when input starts with <keyfile>
        # output also starts with <keyfile>
        print;

        # read next line
        $_ = <IN>;
        $line_num++;
    }

    my ( $rows, $cols );
    if ( defined $opt_dense )
    {
        if ( /^\s*(\d+)\s+(\d+)\s*$/ )
        {
            $rows = $1;
            $cols = $2;
        }
        else
        {
            print STDERR "ERROR($0):
    	Line$line_num in Vector file <$infile> should show 
    	#nrows #ncols when --dense is ON.\n";
            exit;
        }
    }
    else
    {
        if ( /^\s*(\d+)\s+(\d+)\s+(\d+)\s*$/ )
        {
            $rows = $1;
            $cols = $2;
            $nnz1 = $3;
        }
        else
        {
            print STDERR "ERROR($0):
            Line$line_num in Vector file <$infile> should show
            #nrows #ncols #nnz.\n";
            exit;
        }
    }

    my ( $matrix_file, $map_pdl );
    if ( defined $opt_dense )
    {

        # mapping vectors to a temporary file
        $matrix_file = "matrix" . time() . ".simat";
        $map_pdl = mapfraw( "$matrix_file", { Creat => 1, Dims => [ $cols, $rows ], Datatype => double } );

        # reading vectors and storing in mapped piddle
        my $row = 0;
        while ( <IN> )
        {
            s/^\s*//;
            s/\s*$//;
            @vector_comps = split( /\s+/ );
            if ( scalar( @vector_comps ) != $cols )
            {
                print STDERR "ERROR($0):
            Vector $row in Vector file <$infile> doesn't have $cols components.\n";
                exit;
            }
            $map_pdl ( :, $row ) .= pdl @vector_comps;
            $row++;
        }

        if ( $row != $rows )
        {
            print STDERR "ERROR($0):
    	Vector file <$infile> doesn't contain $rows vectors.\n";
            exit;
        }

        # normalizing
        $map_pdl .= $map_pdl->norm;

        # mapping cosine matrix
        my $cos_file = "cosine" . time() . ".simat";
        my $cosine_pdl = mapfraw( "$cos_file", { Creat => 1, Dims => [ $rows, $rows ], Datatype => double } );

        # taking inner product
        $cosine_pdl .= matmult( $map_pdl, $map_pdl->mv( 0, 1 ) );

        # printing
        print "$rows\n";
        foreach my $row ( 0 .. $cosine_pdl->getdim( 1 ) - 1 )
        {
            foreach my $col ( 0 .. $cosine_pdl->getdim( 0 ) - 1 )
            {
                printf( $format, $cosine_pdl->at( $col, $row ) );
            }
            print "\n";
        }

        unlink "$cos_file";
        unlink "$cos_file.hdr";
        unlink "$matrix_file";
        unlink "$matrix_file.hdr";
    }

    # given vectors in sparse format
    else
    {
        $row = 0;
        while ( <IN> )
        {
            $line_num++;
            $row++;
            chomp;
            s/^\s*//;
            s/\s*$//;
            $sparsevec = Math::SparseVector->new;
            @pairs     = split;
            foreach ( $i = 0 ; $i < $#pairs ; $i = $i + 2 )
            {
                my $index = $pairs[ $i ];
                if ( $index > $cols )
                {
                    print STDERR "ERROR($0):
    	Index <$index> at line <$line_num> in Vector file <$infile>
    	exceeds #cols = <$cols> specified in the header line.\n";
                    exit;
                }
                $value = $pairs[ $i + 1 ];
                if ( $value == 0 )
                {
                    print STDERR "ERROR($0):
    	Caught value 0 at line <$line_num> in sparse Vector file <$infile>.\n";
                    exit;
                }
                $sparsevec->set( $index, $value );
                $nnz++;
            }
            push @sparse_vectors, $sparsevec;
        }
        close IN;
        if ( $row != $rows )
        {
            print STDERR "ERROR($0):
    	#rows = $rows specified in the header line of the VECTOR file <$infile>
    	does not match the actual #rows = $row found in the file.\n";
            exit;
        }
        if ( $nnz != $nnz1 )
        {
            print STDERR "ERROR($0):
    	#nnz = $nnz1 specified in the header line of the VECTOR file <$infile>
    	does not match the actual #nnz = $nnz found in the file.\n";
            exit;
        }

        # normalizing all rows
        foreach ( @sparse_vectors )
        {

            # @keys=$_->keys();
            # if($#keys > -1)
            if ( !$_->isnull )
            {
                $_->normalize;
            }
        }
        $nnz = 0;

        # finding cosines
        foreach $i ( 1 .. $rows )
        {
            $cosine{ $i }{ $i } = 1;
            $nnz++;
            foreach $j ( $i + 1 .. $rows )
            {
                $dp = $sparse_vectors[ $i - 1 ]->dot( $sparse_vectors[ $j - 1 ] );
                if ( $dp != 0 )
                {
                    $cosine{ $i }{ $j } = $dp;
                    $cosine{ $j }{ $i } = $dp;
                    $nnz += 2;
                }
            }
        }
        return ( %cosine );
    }

}

1;
