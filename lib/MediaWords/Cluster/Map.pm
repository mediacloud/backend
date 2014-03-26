package MediaWords::Cluster::Map;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# Generate cluster maps from existing media cluster run data.
#
# This module includes common code to get a media cluster run ready to be visualized.
# Should be general enough to work with different server-side layouts
#    (ie GraphVis, Graph::Layout::Aesthetic) and hopefully different client-side
#    ones too (ie Protovis, Google Charts, Processing)

# $nodes ultimately looks like this:
# $nodes = [
#     {
#         name                => "name",
#         clusters_id         => $clusters_id,
#         media_id            => $media_id,
#         linked              => false
#         links => [
#             {
#                 target_id => $target_1_id
#                 weight    => $link_1_weight
#             },
#             ...
#         ]
#         nodes_id             => $node_id
#     },
#     ...
# ]

use strict;

use Data::Dumper;
use List::Util;
use Math::Random;

use MediaWords::Cluster;
use MediaWords::Cluster::Map::GraphViz;
use MediaWords::DBI::DashboardMediaSets;
use MediaWords::DBI::Queries;
use MediaWords::Util::Colors;
use MediaWords::Util::HTML;
use MediaWords::Util::JSON;
use MediaWords::Util::BigPDLVector qw( vector_new vector_cos_sim vector_normalize vector_set vector_cos_sim_cached );

use constant MIN_LINK_WEIGHT => 0.2;
use constant MAX_NUM_LINKS   => 10000;

# Return a hash ref with the number of links and nodes
sub _get_stats
{
    my ( $nodes ) = @_;

    my $nodes_total    = 0;
    my $nodes_rendered = 0;
    my $links_total    = 0;

    for my $node ( @{ $nodes } )
    {
        $nodes_total++ if defined $node->{ name };
        $links_total += scalar @{ $node->{ links } } if defined $node->{ links };
        $nodes_rendered++ if $node->{ linked };
    }

    my $stats = {
        nodes_total    => $nodes_total,
        nodes_rendered => $nodes_rendered,
        links_rendered => $links_total
    };

    return $stats;
}

# get a lookup table of media from the media list of all media_clusters
sub _get_medium_lookup
{
    my ( $media_clusters ) = @_;

    my $medium_lookup = {};
    for my $media_cluster ( @{ $media_clusters } )
    {
        for my $medium ( @{ $media_cluster->{ media } } )
        {
            $medium->{ media_clusters_id } = $media_cluster->{ media_clusters_id };
            $medium_lookup->{ $medium->{ media_id } } = $medium;
        }
    }

    return $medium_lookup;
}

# Assign a single media set to the given node.  The media set for a node
# is the first media set associated with the query that is also associated
# with the node
sub _get_medium_media_sets_id
{
    my ( $clustering_engine, $medium ) = @_;

    return 0 unless $medium;

    my $db    = $clustering_engine->db;
    my $query = $clustering_engine->cluster_run->{ query };

    my ( $node_media_sets_id ) = $clustering_engine->db->query(
        "select msmm.media_sets_id from media_sets_media_map msmm, queries_media_sets_map qmsm " .
          "  where msmm.media_sets_id = qmsm.media_sets_id " .
          "    and qmsm.queries_id = $query->{ queries_id } " . "    and msmm.media_id = $medium->{ media_id }" )->flat;

    return $node_media_sets_id;
}

# given a node row num, a medium, and a media cluster, return a node record
sub _get_medium_node
{
    my ( $clustering_engine, $medium ) = @_;

    my $media_sets_id = _get_medium_media_sets_id( $clustering_engine, $medium );

    return {
        name          => $medium->{ name },
        clusters_id   => $medium->{ media_clusters_id },
        media_id      => $medium->{ media_id },
        url           => $medium->{ url },
        media_sets_id => $media_sets_id,
        linked        => 1
    };
}

# given a query, return a node record
sub _get_query_node
{
    my ( $query ) = @_;

    return {
        name   => $query->{ description },
        query  => 1,
        linked => 1
    };
}

# create the nodes with similarity links for feeding into mapping implementation
sub _get_nodes
{
    my ( $clustering_engine, $sim_list, $media_clusters, $queries ) = @_;

    die "media_clusters cannot be empty" if scalar( @$media_clusters ) == 0;

    my $row_labels     = $clustering_engine->row_labels;
    my $max_medium_row = $#{ $row_labels };

    my $nodes = [];

    my $medium_lookup = _get_medium_lookup( $media_clusters );

    for my $sim ( @{ $sim_list } )
    {
        for my $i ( $sim->[ 0 ], $sim->[ 1 ] )
        {
            if ( !$nodes->[ $i ] )
            {
                if ( $i <= $max_medium_row )
                {
                    $nodes->[ $i ] = _get_medium_node( $clustering_engine, $medium_lookup->{ $row_labels->[ $i ] } );
                }
                else
                {
                    $nodes->[ $i ] = _get_query_node( $queries->[ $i - $max_medium_row - 1 ] );
                }
                $nodes->[ $i ]->{ nodes_id } = $i;
            }
        }
        push(
            @{ $nodes->[ $sim->[ 0 ] ]->{ links } },
            { target_id => $sim->[ 1 ], sim => $sim->[ 2 ], target_media_id => $row_labels->[ $sim->[ 1 ] ] }
        );
    }

    for my $j ( 0 .. $max_medium_row )
    {
        $nodes->[ $j ] ||= _get_medium_node( $clustering_engine, $medium_lookup->{ $row_labels->[ $j ] } );
    }

    return $nodes;
}

# given the nodes, plot them using the given plotting method.
# assigns an 'x' and 'y' field to each node record.
sub _plot_nodes
{
    my ( $method, $nodes ) = @_;

    die "There must be more than one node " if scalar( @$nodes ) <= 1;

    if ( $method =~ /^graphviz/ )
    {
        MediaWords::Cluster::Map::GraphViz::plot_nodes( $method, $nodes );
    }
    else
    {
        die( "Unknown method: '$method'" );
    }
}

# add the given similarity to a list in order of the similarity score,
# with the lowest similarity first, only keeping $max_similarities
# links in the list at any time, and only adding similarities that are
# at least as big as min_similarity
sub _add_to_sim_list
{
    my ( $list, $sim, $max_similarities, $min_similarity ) = @_;

    $list ||= [];

    if ( $sim->[ 2 ] < $min_similarity )
    {
        return $list;
    }

    if ( !@{ $list } )
    {
        unshift( @{ $list }, $sim );
        return $list;
    }

    if ( ( @{ $list } < $max_similarities ) && ( $sim->[ 2 ] <= $list->[ 0 ]->[ 2 ] ) )
    {
        unshift( @{ $list }, $sim );
        return $list;
    }

    for my $i ( 0 .. $#{ $list } )
    {
        if ( $sim->[ 2 ] > $list->[ $i ]->[ 2 ] )
        {
            splice( @{ $list }, $i, 1, $list->[ $i ], $sim );
            last;
        }
    }

    if ( @{ $list } > $max_similarities )
    {
        shift( @{ $list } );
    }

    return $list;
}

# generates a list of similarities in the following form sorted by highest weight first:
# [ matrix_row_1, matrix_row_2, weight ]
#
# return only the top MAX_NUM_LINKS similarity scores greater than MIN_LINK_WEIGHT
sub _get_cosine_sim_list
{
    my ( $clustering_engine, $max_links ) = @_;

    my $sparse_matrix = $clustering_engine->sparse_matrix;
    my $row_labels    = $clustering_engine->row_labels;

    my $max_row  = $#{ $sparse_matrix };
    my $sim_list = [];

    $max_links = ( $max_links > MAX_NUM_LINKS ) ? MAX_NUM_LINKS : $max_links;

    for my $i ( 0 .. $max_row )
    {
        for my $j ( $i + 1 .. $max_row )
        {
            my $dp = vector_cos_sim_cached(
                $sparse_matrix->[ $i ],
                $sparse_matrix->[ $j ],
                $row_labels->[ $i ],
                $row_labels->[ $j ]
            );

            my $sim = [ $i, $j, $dp ];
            $sim_list = _add_to_sim_list( $sim_list, $sim, $max_links, MIN_LINK_WEIGHT );
        }
    }

    return $sim_list;
}

# returns a list of similarities between the polar queries and the media sources
# in the following form sorted by lowest weight first:
# [ < max_matrix_row + query_num >, matrix_row, weight ]
sub _get_pole_cosine_sim_list
{
    my ( $clustering_engine, $queries ) = @_;

    my $sparse_matrix = $clustering_engine->sparse_matrix;
    my $row_labels    = $clustering_engine->row_labels;

    my $max_row  = $#{ $sparse_matrix };
    my $sim_list = [];

    my $pole_row = $max_row;
    for my $query ( @{ $queries } )
    {
        my $pole_vector = $clustering_engine->get_query_vector( $query );
        $pole_row++;

        for my $i ( 0 .. $max_row )
        {

            # say STDERR "row $i ($row_labels->[ $i ]):";
            # say STDERR "****";
            # say STDERR MediaWords::Util::BigPDLVector::vector_string( $sparse_matrix->[ $i ] );
            # say STDERR "****";
            #
            # say STDERR "pole:";
            # say STDERR "****";
            # say STDERR MediaWords::Util::BigPDLVector::vector_string( $pole_vector );
            # say STDERR "****";

            my $dp = vector_cos_sim( $pole_vector, $sparse_matrix->[ $i ] );
            push( @{ $sim_list }, [ $pole_row, $i, $dp, 'query' ] );
            say STDERR "sim $row_labels->[ $i ]: $dp";
        }
    }

    # give the poles negative similarity to each other so that they will be spaced as far apart
    # as possible
    map { push( @{ $sim_list }, [ $max_row + 1, $max_row + 1 + $_, -2 ] ); } ( 1 .. $#{ $queries } );

    return $sim_list;
}

# get all of the media clusters within the given cluster run and
# add a { media } field that has the full media source records
# for all meida sources belonging to the cluster
sub _get_media_clusters
{
    my ( $db, $cluster_run ) = @_;

    print STDERR "_get_media_clusters: " . Dumper( $cluster_run ) . "\n";

    my $media_clusters =
      $db->query( "select * from media_clusters where media_cluster_runs_id = $cluster_run->{ media_cluster_runs_id } " .
          "  order by media_clusters_id" )->hashes;

    my $media =
      $db->query( "select m.*, mc.media_clusters_id from media m, media_clusters mc, media_clusters_media_map mcmm " .
          "  where m.media_id = mcmm.media_id and mcmm.media_clusters_id = mc.media_clusters_id " .
          "    and mc.media_cluster_runs_id = $cluster_run->{ media_cluster_runs_id } " .
          "  order by mc.media_clusters_id, m.media_id " )->hashes;

    # add each media source to the appopriate media cluster, which we can do
    # with a straight loop b/c the above queries are sorted appropriately
    my $i = 0;
    for my $media_cluster ( @{ $media_clusters } )
    {
        while ( ( $i < @{ $media } ) && ( $media->[ $i ]->{ media_clusters_id } == $media_cluster->{ media_clusters_id } ) )
        {
            push( @{ $media_cluster->{ media } }, $media->[ $i++ ] );
        }
    }

    return $media_clusters;
}

# get a suitable name for the cluster map defined by the parameters
sub _get_map_name
{
    my ( $db, $cluster_run, $map_type, $queries, $method ) = @_;

    if ( $map_type eq 'cluster' )
    {
        return 'cluster map - ' . $method;
    }
    elsif ( $map_type eq 'polar' )
    {
        return "polar: " . join( " v. ", map { $_->{ description } } @{ $queries } );
    }
    else
    {
        die( "Unknown map type '$map_type'" );
    }
}

# return the centroids for the plotted nodes, where the centroid represents
# the geographic mean of the plotted coordinates of each node within each of
# the media_clusters included in the cluster run.  This has to
# be run after running the map_nodes() from the mapping implementation
# module (eg. GraphViz).  It returns a list of hashes with the following
# fields: ( x, y, id, name }
sub _get_centroids_from_plotted_nodes
{
    my ( $media_clusters, $nodes ) = @_;

    my $centroids = [];

    for my $cluster ( @{ $media_clusters } )
    {
        my $clusters_id  = $cluster->{ media_clusters_id };
        my $cluster_name = $cluster->{ description };

        my $xTotal = 0;
        my $yTotal = 0;

        my $num_nodes = 0;

        for my $i ( 0 .. $#{ $nodes } )
        {
            if ( my $node = $nodes->[ $i ] )
            {
                if ( $node->{ clusters_id } && ( $node->{ clusters_id } == $clusters_id ) )
                {
                    $xTotal += $node->{ x };
                    $yTotal += $node->{ y };
                    $num_nodes++;
                }
            }
        }

        if ( $num_nodes )
        {
            my $x        = $xTotal / $num_nodes;
            my $y        = $yTotal / $num_nodes;
            my $centroid = { x => $x, y => $y, clusters_id => $clusters_id, name => $cluster_name };
            push( @{ $centroids }, $centroid );
        }
    }

    return $centroids;
}

# get a table that associates each media_sets_id in media_sets with a shape
sub _get_media_set_shape_lookup
{
    my ( $media_sets ) = @_;

    my $lookup = {};

    my $shapes = [ qw(circle triangle diamond square tick bar) ];

    for my $m ( 0 .. $#{ $media_sets } )
    {
        $lookup->{ $media_sets->[ $m ]->{ media_sets_id } } = $shapes->[ $m ] || $shapes->[ 0 ];
    }

    return $lookup;
}

# if the clusters are from a media_sets cluster run and the query
# has a dahsboards_id, then assign consistent colors from the
# dashboard_media_sets table
sub _get_dashboard_media_set_cluster_color_lookup
{
    my ( $db, $media_clusters, $media_sets ) = @_;

    my $cluster_run = $db->find_by_id( 'media_cluster_runs', $media_clusters->[ 0 ]->{ media_cluster_runs_id } );

    return unless ( $cluster_run->{ clustering_engine } eq 'media_sets' );

    my $query = $db->find_by_id( 'queries', $cluster_run->{ queries_id } );

    return unless ( $query->{ dashboards_id } );

    my $lookup;
    for my $media_cluster ( @{ $media_clusters } )
    {
        my $dashboard_media_set = $db->query(
            "select * from dashboard_media_sets where media_sets_id = ? and dashboards_id = ?",
            $media_cluster->{ media_sets_id },
            $query->{ dashboards_id }
        )->hash;
        my $color = MediaWords::DBI::DashboardMediaSets::get_color( $db, $dashboard_media_set );
        $lookup->{ $media_cluster->{ media_clusters_id } } =
          MediaWords::Util::Colors::get_rgbp_format( $dashboard_media_set->{ color } );
    }
}

# get a hash that associates each cluster with a color
sub _get_cluster_color_lookup
{
    my ( $db, $clusters, $media_sets ) = @_;

    my $lookup;

    return $lookup if ( $lookup = _get_dashboard_media_set_cluster_color_lookup( $db, $clusters, $media_sets ) );

    $lookup = {};

    my $colors = MediaWords::Util::get_colors( scalar( @{ $clusters } ), 'rgb()' );

    for my $cluster ( @{ $clusters } )
    {
        $lookup->{ $cluster->{ media_clusters_id } } = pop( @{ $colors } );
    }

    return $lookup;
}

# normalize the coordinates for the given list to range between $max to -$max for both
# the x and y coordinates.  resets the 'x' and 'y' field of each of the
# hashes in the given list to the normalized value.  if a $norm_nodes param is
# passed as the third param, use that norm_data to determine the raw max x and y.
sub _normalize_coordinates
{
    my ( $max, $nodes, $norm_nodes ) = @_;

    $norm_nodes ||= $nodes;

    my ( $x_max, $x_min, $y_max, $y_min );
    for my $node ( @{ $norm_nodes } )
    {
        next if ( !$node->{ clusters_id } );

        my $x = $node->{ x };
        my $y = $node->{ y };

        $x_max = $x if ( !defined( $x_max ) || ( $x > $x_max ) );
        $x_min = $x if ( !defined( $x_min ) || ( $x < $x_min ) );
        $y_max = $y if ( !defined( $y_max ) || ( $y > $y_max ) );
        $y_min = $y if ( !defined( $y_min ) || ( $y < $y_min ) );
    }

    my $x_range = ( $x_max - $x_min ) || 1;
    my $y_range = ( $y_max - $y_min ) || 1;

    for my $node ( @{ $nodes } )
    {
        next if ( !$node->{ x } || !$node->{ y } );

        $node->{ x } = ( ( ( $node->{ x } - $x_min ) / $x_range ) * $max * 2 ) - $max;
        $node->{ y } = ( ( ( $node->{ y } - $y_min ) / $y_range ) * $max * 2 ) - $max;
    }
}

# given the set of nodes, centroids, and media_sets, generate a javascript string
# suitable for assigning to the data variable in 'root/clusters/protovis_transform.tt2'
sub _get_protovis_json
{
    my ( $db, $nodes, $media_clusters, $media_sets ) = @_;

    my $centroids = _get_centroids_from_plotted_nodes( $media_clusters, $nodes );

    my $color_lookup = _get_cluster_color_lookup( $db, $media_clusters, $media_sets );

    for my $n ( @{ $nodes }, @{ $centroids } )
    {
        $n->{ color } = ( $color_lookup->{ $n->{ clusters_id } } || "rgb(0,0,0)" );
    }

    _normalize_coordinates( 10, $centroids, $nodes );
    _normalize_coordinates( 10, $nodes );

    map {
        for my $i ( 0 .. $#{ $_ } ) { $_->[ $i ]->{ i } = $i; }
    } ( $nodes, $centroids, $media_sets );

    return MediaWords::Util::JSON::get_json_from_perl( { nodes => $nodes, clusters => $centroids, sets => $media_sets } );
}

# store the poles and all similarity scores between the poles and each media source
sub _store_poles
{
    my ( $clustering_engine, $cluster_map, $queries, $sim_list ) = @_;

    print STDERR "_store_poles\n";

    return if ( !$queries || !@{ $queries } );

    my $row_labels = $clustering_engine->row_labels;
    my $db         = $clustering_engine->db;

    for ( my $i = 0 ; $i < @{ $queries } ; $i++ )
    {
        print STDERR "_store_poles: query $i\n";
        my $query = $queries->[ $i ];

        my $existing_map_poles = $db->query(
            "select * from media_cluster_map_poles " . "  where media_cluster_maps_id = ? and queries_id = ?",
            $cluster_map->{ media_cluster_maps_id },
            $query->{ queries_id }
        )->hashes;

        if ( !@{ $existing_map_poles } )
        {
            print STDERR "_store_poles: create map pole\n";
            $db->create(
                'media_cluster_map_poles',
                {
                    name                  => $query->{ description },
                    media_cluster_maps_id => $cluster_map->{ media_cluster_maps_id },
                    pole_number           => $i,
                    queries_id            => $query->{ queries_id }
                }
            );
        }
    }

    for my $sim ( @{ $sim_list } )
    {
        my ( $pole_number, $medium_lookup, $similarity ) = @{ $sim };

        $pole_number -= $#{ $row_labels } + 1;
        my $media_id = $row_labels->[ $medium_lookup ];

        print STDERR "_store_poles: add sim $medium_lookup, $media_id, $pole_number, $similarity\n";

        $db->create(
            'media_cluster_map_pole_similarities',
            {
                media_id              => $media_id,
                media_cluster_maps_id => $cluster_map->{ media_cluster_maps_id },
                queries_id            => $queries->[ $pole_number ]->{ queries_id },
                similarity            => int( $similarity * 1000 )
            }
        );
    }
}

# generate the media_cluster_map_pole_similarities rows for the given cluster run if they do not already exist
sub generate_polar_map_sims
{
    my ( $db, $cluster_map, $queries ) = @_;

    print STDERR "generate_polar_map_sims\n";

    my $sims = $db->query( "select * from media_cluster_map_pole_similarities where media_cluster_maps_id = ?",
        $cluster_map->{ media_cluster_maps_id } )->hashes;

    return if ( @{ $sims } );

    print STDERR "generate_polar_map_sims: no db sims\n";

    my $cluster_run = $db->query( "select * from media_cluster_runs where media_cluster_runs_id = ?",
        $cluster_map->{ media_cluster_runs_id } )->hash;

    my $clustering_engine = MediaWords::Cluster->new( $db, $cluster_run, 1 );

    my $media_clusters = _get_media_clusters( $db, $cluster_run );

    my $media_sets = $cluster_run->{ query }->{ media_sets };

    my $sim_list = _get_pole_cosine_sim_list( $clustering_engine, $queries );

    _store_poles( $clustering_engine, $cluster_map, $queries, $sim_list );
}

# generate a media cluster map for a given cluster run
#
# if $queries is passed, generate a polar map using each of the given
# queries as a pole for the map by generating similarities only between
# a media source and each query for each media source.
#
# otherwise if no $queries is passed, generate a default cluster map
# using similarities between each media source.
#
# stores and returns a newly created media_cluster_runs record, which includes
# a 'json_string' field that can be passed to protovis for javascript rendering
sub generate_cluster_map
{
    my ( $db, $cluster_run, $map_type, $queries, $max_links, $method ) = @_;

    my $clustering_engine = MediaWords::Cluster->new( $db, $cluster_run, 1 );

    my $media_clusters = _get_media_clusters( $db, $cluster_run );

    my $media_sets = $cluster_run->{ query }->{ media_sets };

    my $sim_list;
    if ( $queries )
    {
        $sim_list = _get_pole_cosine_sim_list( $clustering_engine, $queries );
    }
    else
    {
        $sim_list = _get_cosine_sim_list( $clustering_engine, $max_links );
    }

    if ( !@{ $sim_list } )
    {
        warn( "not enough data to generate cluster map" );
        return undef;
    }

    my $nodes = _get_nodes( $clustering_engine, $sim_list, $media_clusters, $queries );

    _plot_nodes( $method, $nodes );

    my $json_string = _get_protovis_json( $db, $nodes, $media_clusters, $media_sets );

    my $stats = _get_stats( $nodes );

    my $map_name = _get_map_name( $db, $cluster_run, $map_type, $queries, $method );

    my $cluster_map = $db->create(
        'media_cluster_maps',
        {
            media_cluster_runs_id => $cluster_run->{ media_cluster_runs_id },
            name                  => $map_name,
            method                => $method,
            map_type              => $map_type,
            json                  => $json_string,
            nodes_total           => $stats->{ nodes_total },
            nodes_rendered        => $stats->{ nodes_rendered },
            links_rendered        => $stats->{ links_rendered }
        }
    );

    _store_poles( $clustering_engine, $cluster_map, $queries, $sim_list );

    return $cluster_map;
}

# return a copy of the given query, which is identical to the given query
# in all respects except possibly the start and end dates
sub _get_time_slice_query
{
    my ( $db, $query, $start_date, $end_date ) = @_;

    my $time_slice_params = { %{ $query } };
    $time_slice_params->{ start_date } = $start_date;
    $time_slice_params->{ end_date }   = $end_date;

    return MediaWords::DBI::Queries::find_or_create_query_by_params( $db, $time_slice_params );
}

# return time slices of the given query, identical to the given query but
# covering every 4 week period starting with the query start date
sub _get_query_time_slices
{
    my ( $db, $query ) = @_;

    my $query_time_slices = [];

    my $slice_start_date = $query->{ start_date };
    while ( $slice_start_date lt $query->{ end_date } )
    {
        my $slice_end_date = MediaWords::Util::SQL::increment_day( $slice_start_date, 27 );
        $slice_end_date = List::Util::minstr( $slice_end_date, $query->{ end_date } );

        push( @{ $query_time_slices }, _get_time_slice_query( $db, $query, $slice_start_date, $slice_end_date ) );

        $slice_start_date = MediaWords::Util::SQL::increment_day( $slice_end_date, 1 );
    }

    return $query_time_slices;
}

# look for a cluster run that represents the given time slice query
# for the given clsuter run in the db.  if it doesn't exist,
# create one.
sub _get_time_slice_cluster_run
{
    my ( $db, $cluster_run, $time_slice_query ) = @_;

    my $time_slice_cluster_run = $db->query(
        "select * from media_cluster_runs " . "  where queries_id = ? and source_media_cluster_runs_id = ? ",
        $time_slice_query->{ queries_id },
        $cluster_run->{ media_cluster_runs_id }
    )->hash;

    return $time_slice_cluster_run if ( $time_slice_cluster_run );

    $time_slice_cluster_run = $db->create(
        'media_cluster_runs',
        {
            queries_id                   => $time_slice_query->{ queries_id },
            num_clusters                 => $cluster_run->{ num_clusters },
            clustering_engine            => 'copy',
            state                        => 'pending',
            source_media_cluster_runs_id => $cluster_run->{ media_cluster_runs_id }
        }
    );

    my $clustering_engine = MediaWords::Cluster->new( $db, $time_slice_cluster_run );
    $clustering_engine->execute_and_store_media_cluster_run();

    return $time_slice_cluster_run;
}

# return time sliced versions of any polar queries assocaited
# with the given cluster map.  if the cluster map is not
# of 'polar' type, return undef
sub _get_time_slice_polar_queries
{
    my ( $db, $cluster_map, $time_slice_query ) = @_;

    return undef if ( $cluster_map->{ map_type } ne 'polar' );

    my $time_slice_polar_queries = [];

    my $polar_query_ids = [
        $db->query(
            "select q.queries_id from media_cluster_map_poles mcmp, queries q " .
              "  where mcmp.queries_id = q.queries_id and mcmp.media_cluster_maps_id = ? " .
              "  order by mcmp.pole_number asc",
            $cluster_map->{ media_cluster_maps_id }
        )->flat
    ];
    for my $polar_query_id ( @{ $polar_query_ids } )
    {
        my $polar_query = MediaWords::DBI::Queries::find_query_by_id( $db, $polar_query_id );
        my $time_slice_polar_query =
          _get_time_slice_query( $db, $polar_query, $time_slice_query->{ start_date }, $time_slice_query->{ end_date } );
        push( @{ $time_slice_polar_queries }, $time_slice_polar_query );
    }

    return $time_slice_polar_queries;
}

# return a cluster map based on a time slice of the given cluster map,
# generating one if it does not already exist
sub _get_time_slice_map
{
    my ( $db, $cluster_run, $cluster_map, $time_slice_query ) = @_;

    my $time_slice_cluster_run = _get_time_slice_cluster_run( $db, $cluster_run, $time_slice_query );

    my $time_slice_map = $db->query( "select * from media_cluster_maps where media_cluster_runs_id = ?",
        $time_slice_cluster_run->{ media_cluster_runs_id } )->hash;

    return $time_slice_map if ( $time_slice_map );

    my $time_slice_polar_queries = _get_time_slice_polar_queries( $db, $cluster_map, $time_slice_query );

    $time_slice_map = generate_cluster_map(
        $db, $time_slice_cluster_run, $cluster_map->{ map_type },
        $time_slice_polar_queries,
        $cluster_map->{ links_rendered },
        $cluster_map->{ method }
    );

    return $time_slice_map;
}

# return versions of the given cluster map for every four week period starting with the start date of the
# given cluster map.  if the maps do not already exist, generate new ones.
sub get_time_slice_maps
{
    my ( $db, $cluster_run, $cluster_map ) = @_;

    my $time_slice_queries = _get_query_time_slices( $db, $cluster_run->{ query } );

    my $time_slice_maps = [];
    for my $time_slice_query ( @{ $time_slice_queries } )
    {
        if ( my $time_slice_map = _get_time_slice_map( $db, $cluster_run, $cluster_map, $time_slice_query ) )
        {
            $time_slice_map->{ query } = $time_slice_query;
            push( @{ $time_slice_maps }, $time_slice_map ) if ( $time_slice_map );
        }
    }

    return $time_slice_maps;
}

1;
