package MediaWords::Cluster;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# cluster media sources based on their word vectors

# to generate a cluter run, create new clustering engine by passing in a DBIx::simple db handle and a media_cluster_run
# and then call either execute_media_cluster_run or execute_and_store_media_cluster_run, each of which returns a list
# of the resulting clusters
#
# my $c = MediaWords::Cluster->new( $db, $cluster_run );
# my $clusters = $c->execute_and_store_cluster_run();
# for my $cluster ( @{ $clusters } ) { print "$cluster->{ description }: " . join( ",", @{ $cluster->{ media_ids } } ) ."\n" }
#
# for a full set of fields returned with each cluster, see execute_and_store_media_cluster_run
#
# the clustering engine object has all of the following fields set after calling new():
#
# db - db handle passed to constructor
# cluster_run - media_cluster_run passed to constructor
# query - query referenced by cluster_run field
# media_word_vectors - list of top NUM_MEDIUM_WORDS for each media source in query (see comments above _get_media_word_vectors() )
# stem_vector - lookup table for both stem->term and cross-media-source stem indexes (see comments above _get_stem_vector() )
# sparse_matrix - MediaWords::Util::BigPDLVector sparse matrix of a word vector for each media source
# row_labels - list containing the media_id associated with each row of the sparse_matrix
# col_labels - list containing the stem associated with each column of the sparse_matrix
#
# some of the work done within new() to create these fields from the cluster_run record may be useful for doing other
# clustering related tasks, for example, Cluster::Map uses a cluster object within executing a clustering run to
# generate a cluster map

use strict;
use warnings;

use Data::Dumper;

use Tie::IxHash;

use MediaWords::Cluster::Copy;
use MediaWords::Cluster::Kmeans;
use MediaWords::Cluster::MediaSets;
use MediaWords::Util::Config;
use MediaWords::Util::Timing qw( start_time stop_time );
use MediaWords::Util::BigPDLVector qw( vector_new vector_dot vector_normalize vector_set reset_cos_sim_cache );

# number of nfeatures parameter for the clustering run
use constant NUM_FEATURES => 100;

# Set the minimum frequency for words to appear in the sparse stem matrix
use constant MIN_FREQUENCY => 0;

# number of words to use from each media_source
use constant NUM_MEDIUM_WORDS => 100;

# FIELDS

# { db } DBIx::Simple database handle
# { cluster_run } cluster run
# { media_word_vectors } cached word vectors as described in _get_media_word_vectors() below
# { stem_vector } Tie::IxHash in the form of { < stem > => < term > }

# INTERNAL FUNCTIONS

# query all word vectors for all media. this should be called by new().
#
# returns a list of word records for each media source in the following format:
# { < media_id > => { media_id => < media_id >, stem => { stem }, term => < term >,
#       stem_count => < normalized stem_count >, medium_rank => < word rank> } }
#
# the word rank is the rank from 1 to NUM_MEDIUM_WORDS of the word within the given
# media source.
sub _get_media_word_vectors
{
    my ( $self ) = @_;

    my $db          = $self->db;
    my $cluster_run = $self->cluster_run;

    my $media_word_vectors = {};

    my $query = $cluster_run->{ query };

    my $dashboard_topics_clause = MediaWords::DBI::Queries::get_dashboard_topics_clause( $query, 'mw' );
    my $media_sets_ids_list = join( ',', @{ $query->{ media_sets_ids } } );

    my $words =
      $db->query( "select * from ( " . "  select medium_ms.media_id, mw.stem, min(mw.term) as term, " .
          "      sum( mw.stem_count::float / tw.total_count::float )::float as stem_count, " .
          "      rank() over (partition by medium_ms.media_id " .
          "        order by sum( mw.stem_count::float / tw.total_count::float )::float desc ) as medium_rank " .
          "    from top_500_weekly_words mw, media_sets medium_ms, media_sets collection_ms, " .
          "      media_sets_media_map msmm, total_top_500_weekly_words tw " .
          "    where medium_ms.media_sets_id = mw.media_sets_id " .
          "      and medium_ms.media_id = msmm.media_id and msmm.media_sets_id = collection_ms.media_sets_id " .
          "      and collection_ms.media_sets_id in ( $media_sets_ids_list ) " .
          "      and mw.publish_week between date_trunc( 'week', '$query->{ start_date }'::date) " .
          "      and date_trunc( 'week', '$query->{ end_date }'::date) " . "      and $dashboard_topics_clause " .
          "      and mw.media_sets_id = tw.media_sets_id and mw.publish_week = tw.publish_week " .
          "      and coalesce( mw.dashboard_topics_id, 0 ) = coalesce( tw.dashboard_topics_id, 0 ) " .
          "    group by medium_ms.media_id, mw.stem " .
          "    order by sum( mw.stem_count::float / tw.total_count::float )::float desc ) q " .
          "  where medium_rank <= " . NUM_MEDIUM_WORDS . " " . "  order by media_id, medium_rank" )->hashes;

    for my $word ( @{ $words } )
    {
        push( @{ $media_word_vectors->{ $word->{ media_id } } }, $word );
    }

    return $media_word_vectors;
}

# generate a stem -> term IxHash table of all words in media_word_vectors.  this shoud be called from new()
#
# this table is used for two purposes in the overall clustering process:
# * provide a consistent way of looking up a term for a given stem, particularly for displaying
#   results after the clustering process is finished
# * provide a consistent index for each word for reference during the clustering matrix generation
#   (so that word #34 can refer to the same word across the vector for each separate media source)
#
# the table has to be an IxHash to be able to do both the stem -> term lookup and the
# indexing function.  Note that you have to access the IxHash manually through the ->STORE / ->FETCH / ->INDEX
# methods to be able to use the indexing function.
sub _get_stem_vector
{
    my ( $self ) = @_;

    my $t = Tie::IxHash->new();

    for my $medium_words ( values( %{ $self->media_word_vectors } ) )
    {
        map { $t->STORE( $_->{ stem }, $_->{ term } ) } @{ $medium_words };
    }

    return $t;
}

# get a word stem vector for a single medium as described for _get_stem_matrix
sub _get_medium_stem_vector
{
    my ( $self, $medium, $max_word_rank ) = @_;

    my $words = $self->media_word_vectors->{ $medium->{ media_id } };
    my $stems = $self->stem_vector;

    my $medium_stem_vector = [];
    map { $medium_stem_vector->[ $_ ] = 0 } ( 0 .. ( $stems->Length - 1 ) );

    if ( !$words || !@{ $words } )
    {
        return undef;
    }

    for my $word ( @{ $words } )
    {
        my $p = $word->{ stem_count };
        if ( $p > MIN_FREQUENCY )
        {
            $medium_stem_vector->[ $stems->Indices( $word->{ stem } ) ] = $p;
        }
    }

    return $medium_stem_vector;
}

sub _get_sparse_vector_from_dense_vector
{
    my ( $self, $dense_vector ) = @_;

    return vector_new( 1 ) if ( !@{ $dense_vector } );

    use PDL;
    my $sparse_vector = vector_new( scalar @{ $dense_vector } );

    for my $j ( 0 .. $#{ $dense_vector } )
    {
        my $val = $dense_vector->[ $j ];
        $sparse_vector = vector_set( $sparse_vector, $j, $val );
    }

    return $sparse_vector;
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
sub _get_sparse_matrix
{
    my ( $self, $max_word_rank ) = @_;

    my $db          = $self->db;
    my $cluster_run = $self->cluster_run;
    my $stems       = $self->stem_vector;

    my $media = MediaWords::DBI::Queries::get_media( $db, $cluster_run->{ query } );

    my ( $matrix, $row_labels, $col_labels );

    $matrix     = [];
    $row_labels = [];
    $col_labels = [];

    my $i = 0;
    print STDERR "Adding media sources... ";
    for my $medium ( @{ $media } )
    {
        print STDERR $i++ . " " if ( !( $i % 100 ) );
        if ( my $dense_vector = $self->_get_medium_stem_vector( $medium, $max_word_rank ) )
        {
            my $sparse_vector = $self->_get_sparse_vector_from_dense_vector( $dense_vector );
            push( @{ $matrix },     $sparse_vector );
            push( @{ $row_labels }, $medium->{ media_id } );
        }
    }
    print STDERR "\n";

    @{ $col_labels } = $stems->Keys;

    return ( $matrix, $row_labels, $col_labels );
}

# for each cluster, set the description to the lowest ranked word
# in the given cluster that is ranked lower in the given cluster
# than in any other cluster
sub _add_descriptions_from_features
{
    my ( $self, $clusters ) = @_;

    my $word_ranks;
    for my $c ( 0 .. $#{ $clusters } )
    {
        next if ( $clusters->[ $c ]->{ description } );

        my $words = [ sort { $b->{ weight } <=> $a->{ weight } } @{ $clusters->[ $c ]->{ internal_features } } ];
        for my $w ( 0 .. $#{ $words } )
        {
            $word_ranks->{ $words->[ $w ]->{ stem } }->[ $c ] = $w;
        }

        $clusters->[ $c ]->{ sorted_words } = $words;
    }

    for my $c ( 0 .. $#{ $clusters } )
    {
        next if ( $clusters->[ $c ]->{ description } );

        for my $word ( @{ $clusters->[ $c ]->{ sorted_words } } )
        {
            my $word_has_lowest_rank = 1;
            for my $n ( 0 .. $#{ $clusters } )
            {
                next if ( $n == $c );

                my $other_cluster_rank = $word_ranks->{ $word->{ stem } }->[ $n ];
                if ( defined( $other_cluster_rank ) && ( $other_cluster_rank <= $word_ranks->{ $word->{ stem } }->[ $c ] ) )
                {
                    $word_has_lowest_rank = 0;
                    last;
                }
            }

            if ( $word_has_lowest_rank )
            {
                $clusters->[ $c ]->{ description } = $word->{ term };
                last;
            }
        }

        die( "no description for cluster '$c'" ) if ( !$clusters->[ $c ]->{ description } );

        # in the unlikely case that two clusters are identical, fall back to the first word
        $clusters->[ $c ]->{ description } ||= $clusters->[ $c ]->{ sorted_words }->[ 0 ]->{ term };
    }
}

# add the most common words in each cluster as that cluster's internal features
sub _add_internal_features
{
    my ( $self, $clusters ) = @_;

    # it's a lot quicker to query the media_set directly if we can rather than querying all of the individual media sources
    my $use_media_sets = 0;
    if ( $self->cluster_run->{ clustering_engine } eq 'media_sets' )
    {
        my $cluster_name_lookup = {};
        for my $cluster ( @{ $clusters } )
        {
            $use_media_sets = 0;
            last if ( $cluster_name_lookup->{ $cluster->{ description } } );
            $cluster_name_lookup->{ $cluster->{ description } } = 1;

            $cluster->{ media_set } = $self->db->query(
                "select ms.* from media_sets ms, queries_media_sets_map qmsm " .
                  "  where ms.media_sets_id = qmsm.media_sets_id and qmsm.queries_id = ? " . "    and ms.name = ?",
                $self->cluster_run->{ query }->{ queries_id },
                $cluster->{ description }
              )->hash
              || last;
            $use_media_sets = 1;
        }
    }

    for my $cluster ( @{ $clusters } )
    {
        my $cluster_query;
        if ( $use_media_sets )
        {

            # $cluster_query = MediaWords::DBI::Queries::find_or_create_media_sets_sub_query(
            #     $self->db, $self->cluster_run->{ query }, [ $cluster->{ media_set }->{ media_sets_id } ] );
            my $query = $self->cluster_run->{ query };
            $cluster_query = MediaWords::DBI::Queries::find_or_create_query_by_params(
                $self->db,
                {
                    start_date           => $query->{ start_date },
                    end_date             => $query->{ end_date },
                    dashboard_topics_ids => $query->{ dashboard_topics_ids },
                    media_sets_ids       => [ $cluster->{ media_set }->{ media_sets_id } ]
                }
            );
        }
        else
        {
            $cluster_query = MediaWords::DBI::Queries::find_or_create_media_sub_query(
                $self->db,
                $self->cluster_run->{ query },
                $cluster->{ media_ids }
            );
        }
        my $cluster_words = MediaWords::DBI::Queries::get_top_500_weekly_words( $self->db, $cluster_query );

        splice( @{ $cluster_words }, NUM_FEATURES ) if ( @{ $cluster_words } > NUM_FEATURES );
        map { $_->{ weight } = $_->{ stem_count } } @{ $cluster_words };

        $cluster->{ internal_features } = $cluster_words;
    }
}

# return false if the state is completed and the clustering engine is 'copy' or 'media_sets',
# since neither of those actually need the vectors
sub _needs_vectors
{
    my ( $cluster_run ) = @_;

    return 1 if ( $cluster_run->{ state } ne 'completed' );

    return 0 if ( grep { $cluster_run->{ clustering_engine } eq $_ } qw( media_sets copy ) );

    return 1;
}

# PUBLIC METHODS

sub new
{
    my ( $class, $db, $cluster_run, $force_vectors ) = @_;

    my $self = {};

    $self = bless( $self, $class );

    $self->db( $db );

    $cluster_run->{ query } = MediaWords::DBI::Queries::find_query_by_id( $db, $cluster_run->{ queries_id } );
    $self->cluster_run( $cluster_run );

    # print STDERR "need vector check\n";
    # don't do the expensive vector generation if we're just clustering by media sets
    return $self if ( !$force_vectors && !_needs_vectors( $cluster_run ) );

    # print STDERR "need vector check PASSED\n";

    reset_cos_sim_cache();

    my $t0 = start_time( "caching media word vectors" );
    $self->media_word_vectors( $self->_get_media_word_vectors() );
    stop_time( "caching media word vectors", $t0 );

    $self->stem_vector( $self->_get_stem_vector() );

    $t0 = start_time( "getting sparse matrix" );
    my ( $sparse_matrix, $row_labels, $col_labels ) = $self->_get_sparse_matrix( NUM_MEDIUM_WORDS );
    stop_time( "getting sparse matrix", $t0 );

    $self->sparse_matrix( $sparse_matrix );
    $self->row_labels( $row_labels );
    $self->col_labels( $col_labels );

    return $self;
}

# accessor methods

sub db          { $_[ 0 ]->{ _db }          = $_[ 1 ] if ( defined( $_[ 1 ] ) ); return $_[ 0 ]->{ _db } }
sub query       { $_[ 0 ]->{ _query }       = $_[ 1 ] if ( defined( $_[ 1 ] ) ); return $_[ 0 ]->{ _query } }
sub cluster_run { $_[ 0 ]->{ _cluster_run } = $_[ 1 ] if ( defined( $_[ 1 ] ) ); return $_[ 0 ]->{ _cluster_run } }

sub media_word_vectors
{
    $_[ 0 ]->{ _media_word_vectors } = $_[ 1 ] if ( defined( $_[ 1 ] ) );
    return $_[ 0 ]->{ _media_word_vectors };
}
sub stem_vector   { $_[ 0 ]->{ _stem_vector }   = $_[ 1 ] if ( defined( $_[ 1 ] ) ); return $_[ 0 ]->{ _stem_vector } }
sub sparse_matrix { $_[ 0 ]->{ _sparse_matrix } = $_[ 1 ] if ( defined( $_[ 1 ] ) ); return $_[ 0 ]->{ _sparse_matrix } }
sub row_labels    { $_[ 0 ]->{ _row_labels }    = $_[ 1 ] if ( defined( $_[ 1 ] ) ); return $_[ 0 ]->{ _row_labels } }
sub col_labels    { $_[ 0 ]->{ _col_labels }    = $_[ 1 ] if ( defined( $_[ 1 ] ) ); return $_[ 0 ]->{ _col_labels } }

# given the word vector matrix and other data generated by new(), use
# cluster_run->{ clustering_method } to generate clusters for the
# media sources within the cluster_run->{ query }
#
# returns the list of generated clusters with the following fields:
# * description
# * centroid_media_id
# * media_ids
# * internal_features - list of most common words within cluster, each as { weight => w, stem => s, term => t }
sub execute_media_cluster_run
{
    my ( $self ) = @_;

    my $t0 = start_time( "execute clustering run" );

    my $clusters;
    if ( $self->cluster_run->{ clustering_engine } eq 'kmeans' )
    {
        $clusters = MediaWords::Cluster::Kmeans::get_clusters( $self );
    }
    elsif ( $self->cluster_run->{ clustering_engine } eq 'media_sets' )
    {
        $clusters = MediaWords::Cluster::MediaSets::get_clusters( $self );
    }
    elsif ( $self->cluster_run->{ clustering_engine } eq 'copy' )
    {
        $clusters = MediaWords::Cluster::Copy::get_clusters( $self );
    }
    else
    {
        die "Unknown clustering_engine '" . $self->cluster_run->{ clustering_engine } . "'";
    }

    stop_time( "execute clustering run", $t0 );

    $self->_add_internal_features( $clusters );

    $self->_add_descriptions_from_features( $clusters );

    return $clusters;
}

# store the clusters within the given media_cluster_run
sub store_media_cluster_run
{
    my ( $self, $clusters ) = @_;

    my $db          = $self->db;
    my $cluster_run = $self->cluster_run;

    for my $cluster ( @{ $clusters } )
    {
        my $media_cluster = $db->create(
            'media_clusters',
            {
                media_cluster_runs_id => $cluster_run->{ media_cluster_runs_id },
                description           => $cluster->{ description },
                centroid_media_id     => $cluster->{ centroid_media_id }
            }
        );

        for my $media_id ( @{ $cluster->{ media_ids } } )
        {
            $db->create(
                'media_clusters_media_map',
                {
                    media_clusters_id => $media_cluster->{ media_clusters_id },
                    media_id          => $media_id
                }
            );
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
    }
}

# execute a media cluster run and store the results in the db
# see above comments for execute_media_cluster_run for parameters
# and return values.
sub execute_and_store_media_cluster_run
{
    my ( $self ) = @_;

    my $db          = $self->db;
    my $cluster_run = $self->cluster_run;

    $cluster_run->{ state } = 'executing';
    $db->update_by_id( 'media_cluster_runs', $cluster_run->{ media_cluster_runs_id }, { state => 'executing' } );

    my $clusters = $self->execute_media_cluster_run();

    $self->store_media_cluster_run( $clusters );

    $cluster_run->{ state } = 'completed';
    $db->update_by_id( 'media_cluster_runs', $cluster_run->{ media_cluster_runs_id }, { state => 'completed' } );

    return $clusters;
}

# get a sparse stem vector for the given query including words that are already present
# in the existing stem_vector
sub get_query_vector
{
    my ( $self, $query ) = @_;

    my $words = MediaWords::DBI::Queries::get_top_500_weekly_words( $self->db, $query );

    splice( @{ $words }, NUM_MEDIUM_WORDS ) if ( @{ $words } > NUM_MEDIUM_WORDS );

    my $dense_vector = [];

    # print STDERR $self->cluster_run->{ state } . "\n";
    map { $dense_vector->[ $_ ] = 0 } ( 0 .. ( $self->stem_vector->Length - 1 ) );

    for my $word ( @{ $words } )
    {
        if ( defined( my $index = $self->stem_vector->Indices( $word->{ stem } ) ) )
        {
            $dense_vector->[ $index ] = $word->{ stem_count };
        }
    }

    return $self->_get_sparse_vector_from_dense_vector( $dense_vector );
}

1;
