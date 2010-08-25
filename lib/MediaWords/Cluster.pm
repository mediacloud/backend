package MediaWords::Cluster;

# cluster media sources based on their word vectors

use strict;
use warnings;
use Perl6::Say;
use Data::Dumper;

use Algorithm::Cluster;
use Tie::IxHash;
use Switch 'Perl6';

use MediaWords::Cluster::Kmeans;
use MediaWords::Cluster::Cluto;
use MediaWords::Util::Config;
use MediaWords::Util::Timing qw( start_time stop_time );
use MediaWords::Util::BigPDLVector qw( vector_new vector_add vector_dot vector_div vector_norm
  vector_normalize vector_length vector_nnz vector_get vector_set );

# number of nfeatures parameter for the clustering run
use constant NUM_FEATURES => 50;

# Set the minimum frequency for words to appear in the sparse stem matrix
use constant MIN_FREQUENCY => 0;

# number of words to use from each media_source
use constant NUM_MEDIUM_WORDS => 100;

# cached word vectors in the form of { media_id => [ $top_500_weekly_media_words_hashes ] }
my $_cached_media_word_vectors;

# INTERNAL FUNCTIONS

# query all word vectors for all media
sub _cache_media_word_vectors
{
    my ( $db, $cluster_run ) = @_;

    $_cached_media_word_vectors = undef;

    my $words = $db->query(
        "select * from ( " .
          "  select medium_ms.media_id, mw.stem, min(mw.term) as term, sum(mw.stem_count) as stem_count, " .
          "       rank() over (partition by medium_ms.media_id order by sum(mw.stem_count) desc ) as media_set_rank " .
          "    from top_500_weekly_words mw, media_sets medium_ms, " .
          "       media_sets collection_ms, media_sets_media_map msmm " .
          "    where medium_ms.media_sets_id = mw.media_sets_id " .
          "      and medium_ms.media_id = msmm.media_id and msmm.media_sets_id = collection_ms.media_sets_id " .
          "      and collection_ms.media_sets_id = $cluster_run->{ media_sets_id } " .
          "      and mw.publish_week between date_trunc( 'week', '$cluster_run->{ start_date }'::date) " .
          "      and date_trunc( 'week', '$cluster_run->{ end_date }'::date) + interval '6 days' " .
          "      and mw.dashboard_topics_id is null " .

          # "      and not is_stop_stem( 'long', mw.stem ) " .
          "    group by medium_ms.media_id, mw.stem order by stem_count desc " . "  ) q " . " where media_set_rank <= " .
          NUM_MEDIUM_WORDS . " order by media_id, media_set_rank"
    )->hashes;

    for my $word ( @{ $words } )
    {
        push( @{ $_cached_media_word_vectors->{ $word->{ media_id } } }, $word );
    }
}

# get lookup table of all words that will be included in the clustering word vector.
# returns an IxHash in the form { stem => term } where stem is the stem of the particular word
# and term is the unstemmed version of the word.
sub _get_stem_lookup
{
    my $t = Tie::IxHash->new();

    for my $medium_words ( values( %{ $_cached_media_word_vectors } ) )
    {
        map { $t->STORE( $_->{ stem }, $_->{ term } ) } @{ $medium_words };
    }

    return $t;
}

# get a word stem vector for a single medium as described for _get_stem_matrix
sub _get_medium_stem_vector
{
    my ( $medium, $stems, $max_word_rank ) = @_;

    my $words = $_cached_media_word_vectors->{ $medium->{ media_id } };

    my $all_stem_count = 0;
    map { $all_stem_count += $_->{ stem_count } } @{ $words };

    my $stem_vector = [];
    map { $stem_vector->[ $_ ] = 0 } ( 0 .. ( $stems->Length - 1 ) );

    if ( !@{ $words } )
    {
        return undef;
    }

    for my $word ( @{ $words } )
    {
        my $p         = $word->{ stem_count } / $all_stem_count;
        my $word_rank = $word->{ media_set_rank };
        if ( $p > MIN_FREQUENCY && $word_rank < $max_word_rank )    # Only add words if they are significant enough
        {
            $stem_vector->[ $stems->Indices( $word->{ stem } ) ] = $p;
        }
    }

    return $stem_vector;
}

sub _get_sparse_vector_from_dense_vector
{
    my ( $dense_vector ) = @_;

    use PDL;
    my $sparse_vector = vector_new( scalar @{ $dense_vector } );

    for my $j ( 0 .. $#{ $dense_vector } )
    {
        my $val = $dense_vector->[ $j ];
        $sparse_vector = vector_set( $sparse_vector, $j, $val );
    }

    my $normal_vector = vector_normalize $sparse_vector if defined $sparse_vector;

    return $normal_vector;
}

# get a list of word vectors for the given medium for input to cluto in the form:
# [ [ 2, 0, 9, 1, 0 ],
#   [ 3, 4, 0, 0, 1 ],
#   [ 4, 0, 4, 5, 1 ] ]
# each row represents the word vector for a given medium and each number is the
# prevalence of that word within the given medium.  for prevalence, we use
# the count for the particular word divided by the sum of the counts of all
# of the top 500 words.
#
# return a list with the matrix, the row labels (media id), and the col labels (stems)
# Specify if you want a sparse matrix by sending in $matrix_type as 'sparse'
sub _get_stem_matrix
{
    my ( $db, $cluster_run, $stems, $matrix_type, $max_word_rank ) = @_;

    my $media = $db->query(
        "select distinct m.* from media m, media_sets_media_map msmm " .
          "  where m.media_id = msmm.media_id and msmm.media_sets_id = ? ",
        $cluster_run->{ media_sets_id }
    )->hashes;

    my ( $matrix, $row_labels, $col_labels );

    $matrix     = [];
    $row_labels = [];
    $col_labels = [];

    my $i;
    print STDERR "Adding media sources... ";
    for my $medium ( @{ $media } )
    {
        print STDERR $i++ . " ";
        if ( my $stem_vector = _get_medium_stem_vector( $medium, $stems, $max_word_rank ) )
        {
            if ( $matrix_type eq 'sparse' )
            {
                $stem_vector = _get_sparse_vector_from_dense_vector( $stem_vector );
            }
            push( @{ $matrix },     $stem_vector );
            push( @{ $row_labels }, $medium->{ media_id } );
        }
    }
    print STDERR "\n";

    @{ $col_labels } = $stems->Keys;

    return ( $matrix, $row_labels, $col_labels );
}

# Turn the dense matrix into an array of MediaWords::Util::SparseVectors
sub _get_sparse_matrix_from_dense_matrix
{
    my ( $dense_matrix ) = @_;

    my $sparse_matrix = [];

    for my $i ( 0 .. $#{ $dense_matrix } )
    {
        my $dense_row  = $dense_matrix->[ $i ];
        my $sparse_row = _get_sparse_vector_from_dense_vector( $dense_row );
        push @{ $sparse_matrix }, $sparse_row;
    }

    return $sparse_matrix;
}

# execute the Algorithm::Cluster clustering run and return the results as a list of clusters
# where each cluster is in the form:
# { media_ids => [],
#   internal_features =>  [ { stem => stem, term => term , weight => weight } ],
#   external_features =>  [ { stem => stem, term => term , weight => weight } ] }
sub _get_clusters_ac
{
    my ( $matrix, $row_labels, $col_labels, $stems, $num_clusters ) = @_;

    #say STDERR Dumper($matrix);

    for ( my $x = 0 ; $x < @{ $matrix } ; $x++ )
    {
        my $row = $matrix->[ $x ];

        #print STDERR "ROW $x [" . scalar( @{ $row } ) . "]: " . join("|", map { int ( 1000 * $_ ) } @{ $row } ) . "\n";
        print STDERR "ROW $x " . scalar( @{ $row } ) . " " . $row_labels->[ $x ] . "\n";
    }

    # my ( $raw_clusters, $error, $found ) = Algorithm::Cluster::kcluster(
    #     nclusters => $num_clusters,
    #     data => $matrix,
    #     npass => 10,
    #     );

    my $tree = Algorithm::Cluster::treecluster( data => $matrix, dist => 's' );
    my $raw_clusters = $tree->cut( $num_clusters );

    # kcluster returns an array with the cluster number of media source $i at array position $i.
    # convert to a list of cluster, where each cluster is a hash with the 'media_ids' field pointing
    # to the list of media_ids within that cluster
    my $clusters = [];
    for ( my $i = 0 ; $i < @{ $raw_clusters } ; $i++ )
    {
        my $media_id    = $row_labels->[ $i ];
        my $cluster_num = $raw_clusters->[ $i ];
        push( @{ $clusters->[ $cluster_num ]->{ media_ids } }, $media_id );
    }

    # FIXME: implement internal and external features
    map { $_->{ internal_features } = []; $_->{ external_features } = []; } @{ $clusters };

    return $clusters;
}

# execute the cluto clustering run and return the results as a list of clusters
# where each cluster is in the form:
# { media_ids => [],
#   internal_features =>  [ { stem => stem, term => term , weight => weight } ],
#   external_features =>  [ { stem => stem, term => term , weight => weight } ] }
sub _get_clusters_cluto
{
    return MediaWords::Cluster::Cluto::get_clusters( @_, NUM_FEATURES );
}

sub get_media_source_name
{
    my ( $db, $media_source ) = @_;

    return ( $db->query( "SELECT name from media where media_id = ? ", $media_source )->hashes )[ 0 ]->{ name };
}

sub dump_matrix
{
    my ( $db, $matrix, $row_labels, $col_labels ) = @_;

    use Class::CSV;

    my $fields = [ ( 'media_source', @{ $col_labels } ) ];
    my $csv = Class::CSV->new(
        fields         => $fields,
        line_separator => "\r\n"
    );

    $csv->add_line( $fields );

    open CSV_OUT, ">:utf8", "/tmp/cluster_out.csv";

    my @media_sources = @{ $row_labels };

    foreach my $row ( @{ $matrix } )
    {
        my $media_source = pop @media_sources;

        my $media_source_name = get_media_source_name( $db, $media_source );

        #Get rid of quotations (workaround for spinn3r bug)
        $media_source_name =~ s/"/'/g;

        say STDERR "dumping matrix row for source: $media_source_name";

        my $line = [];

        push @{ $line }, "$media_source_name($media_source)";

        my @row_array = @{ $row };

        foreach my $column_label ( @{ $col_labels } )
        {
            my $row_value = shift @row_array;

            die "undefined row value for $media_source_name" unless defined( $row_value );

            $row_value ||= 0;

            push @{ $line }, $row_value;
        }

        say STDERR "finish matrix row for source: '$media_source_name' line length is " . scalar( @{ $line } );

        $csv->add_line( $line );
        print CSV_OUT $csv->string;
        $csv->lines( [] );
    }

    my $line_count = scalar( @{ $csv->lines } );

    say STDERR "Expecting $line_count lines in the CSV file output.";

    #print CSV_OUT $csv->string;

    say STDERR "CVS output:";

    #print STDERR $csv->string;

    close( CSV_OUT );
}

sub _get_clustering_engine
{
    my $clustering_engine = MediaWords::Util::Config::get_config->{ mediawords }->{ clustering_engine };
    $clustering_engine ||= 'kmeans';
    return $clustering_engine;
}

# Returns a matrix of the cosine similarity between every two media sources
sub _get_cosine_sim_matrix
{
    my ( $sparse_matrix, $row_labels ) = @_;

    # The old Simat.pm... in 6 lines
    my $raw_cosines = {};
    my $rows        = $#{ $sparse_matrix };
    print STDERR "Adding cosines for row # ";
    for my $i ( 0 .. $rows )
    {
        print STDERR "$i ";
        for my $j ( $i + 1 .. $rows )
        {
            my $dp = vector_dot( $sparse_matrix->[ $i ], $sparse_matrix->[ $j ] );
            $raw_cosines->{ $i }->{ $j } = $dp if $dp != 0;
        }
    }

    # Fix media IDs for Cosine matrix
    my $cosines = {};
    while ( my ( $row, $cols ) = each %{ $raw_cosines } )
    {
        while ( my ( $target, $weight ) = each %{ $cols } )
        {
            $cosines->{ $row_labels->[ $row ] }->{ $row_labels->[ $target ] } = $weight;
        }
    }

    return $cosines;
}

# PUBLIC FUNCTIONS

# execute a media cluster run, which is a hash with the following fields:
#
# tags_id: id of tag associated with media sources to cluster
# start_date: start date of clustering run
# end_date: end date of clustering run
# num_clusters: number of clusters into which to divide media sources
#
# return the clusters as described by _get_clusters
sub execute_media_cluster_run
{
    my ( $db, $cluster_run ) = @_;

    print STDERR "\n";

    # Time cache media word vectors
    my $t0 = start_time( "caching media word vectors" );
    _cache_media_word_vectors( $db, $cluster_run );
    stop_time( "caching media word vectors", $t0 );

    my $stems             = _get_stem_lookup();
    my $clustering_engine = _get_clustering_engine();
    my ( $clusters, $cosines );

    if ( $clustering_engine eq 'kmeans' )
    {

        # Time sparse matrix
        $t0 = start_time( "getting sparse matrix" );
        my ( $sparse_matrix, $row_labels, $col_labels ) =
          _get_stem_matrix( $db, $cluster_run, $stems, 'sparse', NUM_MEDIUM_WORDS );
        my ( $criterion_matrix, $criterion_row_labels, $criterion_col_labels ) =
          _get_stem_matrix( $db, $cluster_run, $stems, 'sparse', 100 );
        stop_time( "getting sparse matrix", $t0 );

        # Time cosine sim matrix
        $t0 = start_time( "cosine sim matrix" );
        $cosines = _get_cosine_sim_matrix( $sparse_matrix, $row_labels );
        stop_time( "cosine sim matrix", $t0 );

        # Choose many times to iterate during each cluster run, and how many cluster runs to do
        # These could be user-specified... a speed/quality tradeoff.
        my $num_iterations   = 20;
        my $num_cluster_runs = 20;

        $t0 = start_time( "k-means clustering" );
        $clusters =
          MediaWords::Cluster::Kmeans::get_clusters( $sparse_matrix, $criterion_matrix, $row_labels, $col_labels, $stems,
            $cluster_run->{ num_clusters },
            $num_iterations, $num_cluster_runs );
        stop_time( "k-means clustering", $t0 );
    }
    else
    {
        my ( $dense_matrix, $row_labels, $col_labels ) =
          _get_stem_matrix( $db, $cluster_run, $stems, 'dense', NUM_MEDIUM_WORDS );
        my $sparse_matrix = _get_sparse_matrix_from_dense_matrix( $dense_matrix );
        $cosines = _get_cosine_sim_matrix( $sparse_matrix, $row_labels );

        if ( $clustering_engine eq 'Algorithm::Cluster' )
        {
            $clusters = _get_clusters_ac( $dense_matrix, $row_labels, $col_labels, $stems, $cluster_run->{ num_clusters } );
        }
        elsif ( $clustering_engine eq 'cluto' )
        {
            $clusters =
              _get_clusters_cluto( $dense_matrix, $row_labels, $col_labels, $stems, $cluster_run->{ num_clusters } );
        }
        else
        {
            die "Invalid value for mediawords->clustering_engine $clustering_engine";
        }
    }

    #dump_matrix( $db, $matrix, $row_labels, $col_labels );

    return ( $clusters, $cosines );
}

# if there are any features available for the cluster, use those to create a description
# for the cluster
sub _get_description_from_features
{
    my ( $cluster ) = @_;

    my ( $int_desc, $ext_desc ) = ( '', '' );
    if ( $cluster->{ internal_features } && @{ $cluster->{ internal_features } } )
    {
        $int_desc = $cluster->{ internal_features }->[ 0 ]->{ term };
    }
    if ( $cluster->{ external_features } && @{ $cluster->{ external_features } } )
    {
        $ext_desc = $cluster->{ external_features }->[ 0 ]->{ term };
    }

    my $description = ( $int_desc eq $ext_desc ) ? $int_desc : "$ext_desc $int_desc";

    return $description;
}

# execute a media cluster run and store the results in the db
# arguments and return values are the same as for execute_media_cluster_run
sub execute_and_store_media_cluster_run
{
    my ( $db, $cluster_run ) = @_;

    $db->update_by_id( 'media_cluster_runs', $cluster_run->{ media_cluster_runs_id }, { state => 'executing' } );

    my ( $clusters, $cosines ) = execute_media_cluster_run( $db, $cluster_run );

    # print STDERR "\n\n Clusters: " . Dumper($clusters) . "\n\n";

    $db->update_by_id( 'media_cluster_runs', $cluster_run->{ media_cluster_runs_id }, { state => 'completed' } );

    my $clustering_engine = _get_clustering_engine();

    # Time database writes
    my $t0 = start_time( "writing cluster results to database" );

    for my $cluster ( @{ $clusters } )
    {
        my $description = _get_description_from_features( $cluster ) || 'cluster';

        my $media_cluster = $db->create(
            'media_clusters',
            {
                media_cluster_runs_id => $cluster_run->{ media_cluster_runs_id },
                description           => $description,
                centroid_id           => $cluster->{ centroid_id }
            }
        );

        # keep track of where you are in the internal/external zscore arrays
        my $media_id_cnt = 0;

        for my $media_id ( @{ $cluster->{ media_ids } } )
        {

            $db->create(
                'media_clusters_media_map',
                {
                    media_clusters_id => $media_cluster->{ media_clusters_id },
                    media_id          => $media_id
                }
            );

            # put internal/external zscores and similarities in the database
            $db->create(
                'media_cluster_zscores',
                {
                    media_cluster_runs_id => $cluster_run->{ media_cluster_runs_id },
                    media_clusters_id     => $media_cluster->{ media_clusters_id },
                    media_id              => $media_id,
                    internal_zscore       => $cluster->{ internal_zscores }->[ $media_id_cnt ] || 0,
                    internal_similarity   => $cluster->{ internal_similarity } || 0,
                    external_zscore       => $cluster->{ external_zscores }->[ $media_id_cnt ] || 0,
                    external_similarity   => $cluster->{ external_similarity } || 0
                }
            );

            $media_id_cnt++;
        }

        for my $int_feature ( @{ $cluster->{ internal_features } } )
        {
            if ( defined $int_feature )
            {

                $db->create(
                    'media_cluster_words',
                    {
                        media_clusters_id => $media_cluster->{ media_clusters_id },
                        internal          => 't',
                        weight            => $int_feature->{ weight },
                        stem              => $int_feature->{ stem },
                        term              => $int_feature->{ term }
                    }
                );
            }
        }

        for my $ext_feature ( @{ $cluster->{ external_features } } )
        {
            $db->create(
                'media_cluster_words',
                {
                    media_clusters_id => $media_cluster->{ media_clusters_id },
                    internal          => 'f',
                    weight            => $ext_feature->{ weight },
                    stem              => $ext_feature->{ stem },
                    term              => $ext_feature->{ term }
                }
            );
        }
    }

    # Store links from the cosine matrix

    $db->begin_work;
    print STDERR "Writing links: source # ";
    my $cnt = 0;
    while ( my ( $source, $cols ) = each %{ $cosines } )
    {
        print STDERR $cnt++ . " ";
        while ( my ( $target, $weight ) = each %{ $cols } )
        {
            $db->create(
                'media_cluster_links',
                {
                    media_cluster_runs_id => $cluster_run->{ media_cluster_runs_id },
                    source_media_id       => $source,
                    target_media_id       => $target,
                    weight                => $weight
                }
            );
        }
    }
    print STDERR "\n";
    $db->commit;

    stop_time( "writing cluster results to database...", $t0 );

    return $clusters;
}

1;
