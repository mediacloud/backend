package MediaWords::Cluster::Cluto;
use MediaWords::CommonLibs;

# This module provides an interface to the cluto clustering toolkit based on the command line binaries rather
# than the libray.  We use this module because the library distributed by cluto does not work on
# some linux platforms for which the command line processes do work

# to use this module, you must have set the

use strict;

use File::Temp;
use MediaWords::Util::Config;

# convert a regular matrix into a cluto sparse matrix described as:
# # loading 4x5 sparse matrix
#   #
#   # 1 1 0 1 1
#   # 1 0 0 1 0
#   # 0 1 1 0 0
#   # 0 0 1 0 0
#
#   my $c = new Statistics::Cluto;
#   my $nrows = 4;
#   my $ncols = 5;
#   my $rowval = [
#     [1, 1, 2, 1, 4, 1, 5, 1],
#     [1, 1, 4, 1],
#     [2, 1, 3, 1],
#     [3, 1]
#   ];
#   $c->set_sparse_matrix($nrows, $ncols, $rowval)
sub _get_sparse_matrix
{
    my ( $matrix ) = @_;

    my $sparse_matrix = [];
    for ( my $i = 0 ; $i < @{ $matrix } ; $i++ )
    {
        my $dense_row  = $matrix->[ $i ];
        my $sparse_row = [];
        for ( my $j = 0 ; $j < @{ $dense_row } ; $j++ )
        {
            my $val = $dense_row->[ $j ];
            if ( $val > 0 )
            {
                push( @{ $sparse_row }, $j + 1, $val );
            }
        }

        push( @{ $sparse_matrix }, $sparse_row );
    }

    return $sparse_matrix;
}

# write the sparse matrix to a file in the cluto format and return the name of the file
# This is now "public"; used in generating matrix for Simat.pm
sub _get_sparse_matrix_file
{
    my ( $matrix ) = @_;

    my $sparse_matrix = _get_sparse_matrix( $matrix );

    my ( $fh, $file ) = File::Temp::tempfile();

    if ( !@{ $matrix } || !@{ $matrix->[ 0 ] } )
    {
        die( "matrix is empty" );
    }

    my $num_rows = @{ $matrix };
    my $num_cols = @{ $matrix->[ 0 ] };

    my $num_entries;
    map { $num_entries += ( @{ $_ } / 2 ) } @{ $sparse_matrix };

    $fh->print( "$num_rows $num_cols $num_entries\n" );

    map { $fh->print( join( " ", @{ $_ } ) . "\n" ); } @{ $sparse_matrix };

    $fh->close;

    return $file;
}

# write the col labels to a file and return the name of the file
sub _get_clabel_file
{
    my ( $col_labels ) = @_;

    my ( $fh, $file ) = File::Temp::tempfile;

    binmode( $fh, ':utf8' );

    for my $col_label ( @{ $col_labels } )
    {
        $fh->print( "$col_label\n" );
    }

    $fh->close();

    return $file;
}

# run cluto binary on matrix and return a list containing:
# * the summary statistics printed to stdout by vcluster
# * the contents of the clustering file
#
# see cluto docs for format of each
sub _run_cluto
{
    my ( $matrix, $row_labels, $col_labels, $stems, $num_clusters, $num_features ) = @_;

    my $cluto_binary = MediaWords::Util::Config::get_config->{ mediawords }->{ cluto_binary }
      || die( "Unable to find mediawords->cluto_binary config setting" );

    my $matrix_file = _get_sparse_matrix_file( $matrix );

    # my $clabel_file = _get_clabel_file( $col_labels );

    # free up memory from dense matrix
    while ( shift( @{ $matrix } ) ) { }

    my $cluster_file = "$matrix_file.clustering.$num_clusters";

    # my $cmd = "$cluto_binary -colmodel=none -rowmodel=none -showfeatures -nfeatures $num_features -ntrials=10 -zscores " .
    #     "-clmethod=direct -clabelfile=$clabel_file $matrix_file $num_clusters";
    my $cmd =
      "$cluto_binary -colmodel=none -rowmodel=none -showfeatures -nfeatures $num_features -ntrials=10 -zscores " .
      "-clmethod=direct $matrix_file $num_clusters";

    # print STDERR "$cmd\n";
    # print STDERR "$matrix_file\n";
    # print STDERR "$cluster_file\n";

    if ( !open( CLUTO_CMD, "$cmd|" ) )
    {
        die( "Unable to start cluto '$cmd': $!" );
    }

    my $summary_output = join( "", <CLUTO_CMD> );

    close( CLUTO_CMD );

    if ( !open( CLUSTER_FILE, $cluster_file ) )
    {
        die( "Unable to open cluster file '$cluster_file': $!" );
    }

    my $cluster_output = join( "", <CLUSTER_FILE> );

    close( CLUSTER_FILE );

    return ( $summary_output, $cluster_output );
}

# cluto returns a cluster vector where each line has the cluster id and zscores for each
# media source.  We convert this to a clusters list with the following format:
# [ { media_ids => [ 1, 2, 3, ... ],
#     internal_zscores => [ 1, 2, 1, ... ],
#     external_zscores => [ 10, 20, 10, ... ] } ]
sub _get_clusters_from_vector
{
    my ( $row_labels, $cluster_vector ) = @_;

    my $clusters = [];

    my @cluster_vector_lines = split( "\n", $cluster_vector );

    for ( my $i = 0 ; $i < @cluster_vector_lines ; $i++ )
    {
        my $line = $cluster_vector_lines[ $i ];
        chomp( $line );

        $line =~ s/nan/.001/g;
        $line =~ s/inf/1000/g;

        if ( !( $line =~ /^([0-9\-]+) ([0-9\.\-]+) ([0-9\.\-]+)$/ ) )
        {
            die( "Unable to parse line: '$line'" );
        }

        my ( $cluster_id, $internal_zscore, $external_zscore ) = ( $1, $2, $3 );

        if ( $cluster_id >= 0 )
        {
            push( @{ $clusters->[ $cluster_id ]->{ media_ids } },        $row_labels->[ $i ] );
            push( @{ $clusters->[ $cluster_id ]->{ internal_zscores } }, $internal_zscore );
            push( @{ $clusters->[ $cluster_id ]->{ external_zscores } }, $external_zscore );
        }
    }

    return $clusters;
}

# parse cluster summary stats from cluto output and add to the given clusters
#
# format of relevant part of output to parse:
# 0    43 +0.289 +0.110 +0.050 +0.025 |
# 1    19 +0.259 +0.123 +0.023 +0.018 |
# 2    34 +0.249 +0.082 +0.023 +0.017 |
sub _add_cluster_stats_from_output
{
    my ( $clusters, $cluto_output ) = @_;

    print STDERR "\n\n" . $cluto_output . "\n\n";

    while ( $cluto_output =~ /\s+(\d+)\s+(\d+)\s+([0-9\+\-\.]+)\s+([0-9\+\-\.]+)\s+([0-9\+\-\.]+)\s+([0-9\+\-\.]+)/g )
    {
        my ( $id, $size, $internal_similarity, $internal_stddev, $external_similarity, $external_stddev ) =
          ( $1, $2, $3, $4, $5, $6 );

        $clusters->[ $id ]->{ size }                = $size;
        $clusters->[ $id ]->{ internal_similarity } = $internal_similarity;
        $clusters->[ $id ]->{ internal_stddev }     = $internal_stddev;
        $clusters->[ $id ]->{ external_similarity } = $external_similarity;
        $clusters->[ $id ]->{ external_stddev }     = $external_stddev;
    }
}

# return a list of word features from the string returned by cluto.
# features are returned in the format: { stem => $stem, term => $term, weight => $weight }
#
# parsed string format:
# foo 76.0%, bar  2.6%, [...]
sub _get_features_from_string
{
    my ( $features_string, $col_labels, $stems ) = @_;

    # print STDERR "features_string: $features_string\n";

    my $features;
    while ( $features_string =~ /col([0-9]+)\s+([0-9\.]+)\%/g )
    {
        my ( $col_id, $weight ) = ( $1 - 1, $2 + 0 );

        # print STDERR "col: $col_id, $weight\n";
        my $stem = $col_labels->[ $col_id ];

        # lookup term for the stem in the $stems IxHash
        my $term = $stems->FETCH( $stem );

        push( @{ $features }, { stem => $stem, term => $term, weight => $weight } );
    }

    return $features;
}

# parse cluster summary output for cluster features and add to the given clusters.
#
# relevant summary output format:
# Cluster   0, Size:    43, ISim: 0.289, ESim: 0.050
#       Descriptive:  col00328 76.0%, col00334  2.6%, [...]
#    Discriminating:  col00328 49.3%, col00412 10.2%, [...]
sub _add_cluster_features_from_output
{
    my ( $clusters, $cluto_output, $col_labels, $stems ) = @_;

    while ( $cluto_output =~ /Cluster\s+(\d+),\s+Size:/g )
    {
        my $cluster_id = $1;

        if ( !( $cluto_output =~ /Descriptive:\s+([^A-Z]+)/gc ) )
        {
            die( "Unable to find descriptive features: $cluto_output" );
        }
        my $internal_features_string = $1;

        if ( !( $cluto_output =~ /Discriminating:\s+([^A-Z]+)/gc ) )
        {
            die( "Unable to find discriminating features: $cluto_output" );
        }
        my $external_features_string = $1;

        $clusters->[ $cluster_id ]->{ internal_features } =
          _get_features_from_string( $internal_features_string, $col_labels, $stems );
        $clusters->[ $cluster_id ]->{ external_features } =
          _get_features_from_string( $external_features_string, $col_labels, $stems );
    }
}

# return a list of word features from the string returned by cluto.
# features are returned in the format: { stem => $stem, term => $term, weight => $weight }
#
# parsed string format:
# foo 76.0%, bar  2.6%, [...]
sub _get_features_from_string_labelled
{
    my ( $features_string, $col_labels, $stems ) = @_;

    # print STDERR "features_string: $features_string\n";

    my $features;
    while ( $features_string =~ /(\w+)\s+([0-9\.]+)\%/g )
    {
        my ( $col_id, $weight ) = ( $1 - 1, $2 + 0 );

        my $stem = $col_labels->[ $col_id ];

        # lookup term for the stem in the $stems IxHash
        my $term = $stems->FETCH( $stem );

        push( @{ $features }, { stem => $stem, term => $term, weight => $weight } );
    }

    return $features;
}

# parse cluster summary output for cluster features and add to the given clusters.
#
# relevant summary output format:
# Cluster   0, Size:    43, ISim: 0.289, ESim: 0.050
#       Descriptive:  foo 76.0%, bar  2.6%, [...]
#    Discriminating:  foo 49.3%, bar 10.2%, [...]
sub _add_cluster_features_from_output_labelled
{
    my ( $clusters, $cluto_output, $col_labels, $stems ) = @_;

    while ( $cluto_output =~ /Cluster\s+(\d+),\s+Size:/g )
    {
        my $cluster_id = $1;

        if ( !( $cluto_output =~ /Descriptive:\s+([^A-Z]+)/gc ) )
        {
            die( "Unable to find descriptive features: $cluto_output" );
        }
        my $internal_features_string = $1;

        if ( !( $cluto_output =~ /Discriminating:\s+([^A-Z]+)/gc ) )
        {
            die( "Unable to find discriminating features: $cluto_output" );
        }
        my $external_features_string = $1;

        $clusters->[ $cluster_id ]->{ internal_features } =
          _get_features_from_string( $internal_features_string, $col_labels, $stems );
        $clusters->[ $cluster_id ]->{ external_features } =
          _get_features_from_string( $external_features_string, $col_labels, $stems );
    }
}

# execute the cluto clustering run and return the results as a list of clusters
# where each cluster is in the form:
# { media_ids => [],
#   internal_features =>  [ { stem => stem, term => term , weight => weight } ],
#   external_features =>  [ { stem => stem, term => term , weight => weight } ] }
#
# uses the cluto command line to run the clustering and parses out the resulting cluster file and summary results
sub _get_clusters
{
    my ( $cluster, $matrix, $row_labels, $col_labels ) = @_;

    my $stems        = $cluster->{ stem_vector };
    my $num_clusters = $cluster->{ cluster_run }->{ num_clusters };

    #my $sparse_matrix = _get_sparse_matrix( $matrix );

    my ( $summary, $cluster_vector ) = _run_cluto( @_ );

    # print STDERR "$summary\n\n\n";

    my $clusters = _get_clusters_from_vector( $row_labels, $cluster_vector );

    _add_cluster_stats_from_output( $clusters, $summary );
    _add_cluster_features_from_output( $clusters, $summary, $col_labels, $stems );

    # print STDERR "labels:\n";
    # for ( my $i = 0; $i < @{ $col_labels }; $i++ )
    # {
    #     print STDERR "$i: $col_labels->[ $i ]\n";
    # }

    # use Data::Dumper;
    # print STDERR Dumper( $clusters );

    return $clusters;
}

1;
