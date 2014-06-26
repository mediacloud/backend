package MediaWords::Util::CountryAnalysis;

# generate a variety of analysis results by calling functions on various combinations of media sets and topics.  see get_results for the
# format of the input.  See the functions lists below for the sorts of functions called on various combinations of media sets and topics.

use strict;
use warnings;

use Data::Dumper;

use MediaWords::Cluster;
use MediaWords::Cluster::Map;
use MediaWords::DBI::Queries;
use MediaWords::Util::CSV;

# the following statics are all set via the call to get_results.  see get_results below for format of these variables;

my ( $_base_url, $_media_sets, $_media_set_groups, $_pole_media_sets, $_topic_names, $_topic_dates, $_default_topic_dates );

# list of functions to call for each topic
# format: func( $db, $topic )
my $_global_functions = [ [ 'overall_query', \&get_overall_query_url ], [ 'term_freq', \&get_term_freq_url ], ];

# list of functions to run on each pole / topic combination
# format: func( $db, $topic, $media_set_pole_name )
my $_pole_functions = [ [ 'map', \&get_polar_map_url ], ];

# list of functions to be run on each media-set-or-group / topic combination
# format: func( $db, $topic, $media_set_or_group_name )
my $_media_set_functions = [ [ 'media_sets_query', \&get_media_sets_query_url ], ];

# list of functions to be run on each media-set-or-group / media-set-or-group / topic combination
# format: func( $db, $topic, $media_set_or_group_name, $media_set_or_group_name )
my $_comparison_functions = [ [ 'cloud', \&get_comparative_word_cloud_url ], ];

# list of functions to be run on each media-set-or-group / media-set-pole / topic combination
# format: func( $db, $topic, $media_set_or_group_name, $media_set_pole_name )
my $_media_set_pole_functions = [
    [ 'similarity_mean',     \&get_similarity_mean ],
    [ 'similarity_stddev',   \&get_similarity_stddev ],
    [ 'similarity_skewness', \&get_similarity_skewness ],
    [ 'similarity_kurtosis', \&get_similarity_kurtosis ],
];

# hash of row header names along with an ordinal sort value for each
my $_row_header_order = {};

# turn a 2d matrix into a flat list
sub flatten
{
    my ( $list ) = @_;

    my $flat = [];

    map { push( @{ $flat }, ( ref( $_ ) eq 'ARRAY' ) ? @{ $_ } : $_ ) } @{ $list };

    return $flat;
}

# fetch the media set from the db and fill in any missing info in the record
sub fetch_media_set
{
    my ( $db, $media_set ) = @_;

    my $fetched_media_set;
    if ( $media_set->{ media_sets_id } )
    {
        $fetched_media_set =
          $db->query( 'select * from media_sets where media_sets_id = ?', $media_set->{ media_sets_id } )->hash
          || die( "Unable to find media set for id $media_set->{ media_sets_id }" );
    }
    elsif ( $media_set->{ name } )
    {
        $fetched_media_set = $db->query( 'select * from media_sets where name = ?', $media_set->{ name } )->hash
          || die( "Unable to find media set '$media_set->{ name }'" );
    }
    else
    {
        die( "No name or media_sets_id field" );
    }

    while ( my ( $name, $val ) = each( %{ $fetched_media_set } ) )
    {
        $media_set->{ $name } = $val;
    }

}

# fetch all media sets in $_media_sets and fill in the missing info in the records
sub fetch_media_sets
{
    my ( $db ) = @_;

    map { fetch_media_set( $db, $_ ) } @{ $_media_sets };

    for my $media_set_group ( @{ $_media_set_groups } )
    {
        $media_set_group->{ media_sets } =
          [ map { get_media_set( $db, $_ ) } @{ $media_set_group->{ media_set_nicknames } } ];
    }
}

# return a list of all media sets ids in $_media_sets
sub get_all_media_sets_ids
{

    return [ map { $_->{ media_sets_id } } @{ $_media_sets } ];
}

# get teh start and end dates of the given topic, as determined by $_topic_dates
sub get_topic_dates
{
    my ( $topic ) = @_;

    my ( $start_date, $end_date );
    if ( my $dates = $_topic_dates->{ $topic->{ name } } )
    {
        ( $start_date, $end_date ) = @{ $dates };
    }
    else
    {
        ( $start_date, $end_date ) = @{ $_default_topic_dates };
    }

    return ( $start_date, $end_date );
}

# get the query corresponding to all media sets with no topic
sub get_overall_query_no_topic
{
    my ( $db, $topic ) = @_;

    my ( $start_date, $end_date ) = get_topic_dates( $topic );

    return MediaWords::DBI::Queries::find_or_create_query_by_params(
        $db,
        {
            start_date     => $start_date,
            end_date       => $end_date,
            media_sets_ids => get_all_media_sets_ids()
        }
    );
}

# get the query corresponding to all media sets for the given topic
sub get_overall_query
{
    my ( $db, $topic ) = @_;

    my ( $start_date, $end_date ) = get_topic_dates( $topic );

    return MediaWords::DBI::Queries::find_or_create_query_by_params(
        $db,
        {
            start_date           => $start_date,
            end_date             => $end_date,
            media_sets_ids       => get_all_media_sets_ids(),
            dashboard_topics_ids => [ $topic->{ dashboard_topics_id } ]
        }
    );
}

# get the overall query url for all media sets
sub get_overall_query_url
{
    my ( $db, $topic ) = @_;

    my $query = get_overall_query( $db, $topic );

    return "$_base_url/queries/view/" . $query->{ queries_id };
}

# find or create a cluster run for the given query
sub find_or_create_cluster_run
{
    my ( $db, $topic ) = @_;

    my $query = get_overall_query( $db, $topic );

    my $cluster_run =
      $db->query( "select * from media_cluster_runs where clustering_engine = 'media_sets' and queries_id = ?",
        $query->{ queries_id } )->hash;

    $cluster_run ||= $db->create(
        'media_cluster_runs',
        {
            clustering_engine => 'media_sets',
            queries_id        => $query->{ queries_id },
            num_clusters      => scalar( @{ get_all_media_sets_ids() } )
        }
    );

    if ( $cluster_run->{ state } ne 'completed' )
    {
        my $clustering_engine = MediaWords::Cluster->new( $db, $cluster_run );
        $clustering_engine->execute_and_store_media_cluster_run();
    }

    return $cluster_run;
}

# get query for the given topic and media set or sets
sub get_media_sets_query
{
    my ( $db, $topic, $media_set_params ) = @_;

    if ( !( ( ref( $media_set_params ) || '' ) eq 'ARRAY' ) )
    {
        $media_set_params = [ $media_set_params ];
    }

    my $media_sets = [];
    for my $media_set_param ( @{ $media_set_params } )
    {
        if ( !ref( $media_set_param ) )
        {
            $media_set_param = get_media_set( $db, $media_set_param );
        }

        push( @{ $media_sets }, $media_set_param );
    }

    my ( $start_date, $end_date ) = get_topic_dates( $topic );
    my $media_sets_ids = [ map { $_->{ media_sets_id } } @{ $media_sets } ];

    return MediaWords::DBI::Queries::find_or_create_query_by_params(
        $db,
        {
            start_date           => $start_date,
            end_date             => $end_date,
            media_sets_ids       => $media_sets_ids,
            dashboard_topics_ids => [ $topic->{ dashboard_topics_id } ]
        }
    );

}

# return the media set with the given name from the cached $_media_sets
sub get_media_set
{
    my ( $db, $name ) = @_;

    my @matching_media_sets = grep { ( $_->{ name } eq $name ) || ( $_->{ nickname } eq $name ) } @{ $_media_sets };

    die( "Unable to find media set '$name'" ) if ( !@matching_media_sets );

    return $matching_media_sets[ 0 ];
}

# find or create a polar cluster map for the given cluster run and media set pole
sub find_or_create_polar_map
{
    my ( $db, $cluster_run, $polar_query ) = @_;

    my $cluster_map = $db->query(
        "select * from media_cluster_maps mcm, media_cluster_map_poles mcmp " .
          "  where mcm.media_cluster_maps_id = mcmp.media_cluster_maps_id " .
          "    and mcmp.queries_id = ? and mcm.media_cluster_runs_id = ?",
        $polar_query->{ queries_id },
        $cluster_run->{ media_cluster_runs_id }
    )->hash;

    if ( $cluster_map )
    {
        MediaWords::Cluster::Map::generate_polar_map_sims( $db, $cluster_map, [ $polar_query ] );
    }
    else
    {
        $cluster_map =
          MediaWords::Cluster::Map::generate_cluster_map( $db, $cluster_run, 'polar', [ $polar_query ], 0,
            'graphviz-neato' );
    }

    return $cluster_map;
}

# get a polar map url for the given topic with the media set of the given name at the pole
sub get_polar_map_url
{
    my ( $db, $topic, $polar_media_set_name ) = @_;

    print STDERR Dumper( $polar_media_set_name ) . "\n";

    my $cluster_run = find_or_create_cluster_run( $db, $topic );

    my $polar_query = get_media_sets_query( $db, $topic, $polar_media_set_name );

    my $cluster_map = find_or_create_polar_map( $db, $cluster_run, $polar_query );

    return "$_base_url/clusters/view/" .
      $cluster_run->{ media_cluster_runs_id } . "?media_cluster_maps_id=" . $cluster_map->{ media_cluster_maps_id };
}

# get the term freq for the given term within the overall query
sub get_term_freq_url
{
    my ( $db, $topic ) = @_;

    my $query = get_overall_query_no_topic( $db, $topic );

    my $esc_term = URI::Escape::uri_escape_utf8( $topic->{ query } );

    return "$_base_url/queries/terms/" . $query->{ queries_id } . "?terms=${ esc_term }";
}

# given two media sets or a media set group and a media set, return a
# media set pair in the form { nickname => $n, a => [ $a1, ... ], b => [ $b, ... ] }
sub make_media_set_pair
{
    my ( $a, $b ) = @_;

    my $ms_a = ( $a->{ media_sets } ) ? $a->{ media_sets } : [ $a ];
    my $ms_b = ( $b->{ media_sets } ) ? $b->{ media_sets } : [ $b ];

    my $pair = {
        'nickname' => "$a->{ nickname }_v_$b->{ nickname }",
        a          => $ms_a,
        b          => $ms_b
    };

    return $pair;

}

# return each possible permutation of pairs of the set of all $_media_sets or $_media_set_groups
# with param set to true
sub get_media_set_comparison_pairs
{
    my $media_sets = [ grep { $_->{ compare } } @{ $_media_sets } ];
    my $groups     = [ grep { $_->{ compare } } @{ $_media_set_groups } ];

    my $pairs = [];

    for ( my $i = 0 ; $i < @{ $media_sets } ; $i++ )
    {
        for ( my $j = 0 ; $j < $i ; $j++ )
        {
            push( @{ $pairs }, make_media_set_pair( $media_sets->[ $i ], $media_sets->[ $j ] ) );
        }
    }

    for ( my $g = 0 ; $g < @{ $groups } ; $g++ )
    {
        for ( my $m = 0 ; $m < @{ $media_sets } ; $m++ )
        {
            push( @{ $pairs }, make_media_set_pair( $groups->[ $g ], $media_sets->[ $m ] ) );
        }

        for ( my $gb = 0 ; $gb < $g ; $gb++ )
        {
            push( @{ $pairs }, make_media_set_pair( $groups->[ $g ], $groups->[ $gb ] ) );
        }
    }

    return $pairs;
}

# get a comparative word cloud for the two media sets
sub get_comparative_word_cloud_url
{
    my ( $db, $topic, $media_set_1, $media_set_2 ) = @_;

    my $query_1 = get_media_sets_query( $db, $topic, $media_set_1 );
    my $query_2 = get_media_sets_query( $db, $topic, $media_set_2 );

    #http://amanda.law.harvard.edu/admin/queries/compare?queries_id_2=88463&queries_id=88471
    return "$_base_url/queries/compare?queries_id=" . $query_1->{ queries_id } . "&queries_id_2=" . $query_2->{ queries_id };
}

# add a row header, so that we can retrieve them later with get_ordered_row_headers to print the csv
sub add_row_header
{
    my ( $header ) = @_;

    print STDERR "$header ...\n";

    $_row_header_order->{ $header } ||= scalar( values( %{ $_row_header_order } ) );
}

# get a list of all media sets and media set groups, each as a list of media sets
sub get_all_media_sets_as_groups
{
    my $groups = [];

    map { push( @{ $groups }, { nickname => $_->{ nickname }, media_sets => [ $_ ] } ) } @{ $_media_sets };

    map { push( @{ $groups }, $_ ) } @{ $_media_set_groups };

    return $groups;
}

# get the url for the query for the specific media set (actually list of media sets)
sub get_media_sets_query_url
{
    my ( $db, $topic, $media_sets ) = @_;

    my $query = get_media_sets_query( $db, $topic, $media_sets );

    return "$_base_url/queries/view/" . $query->{ queries_id };
}

# get the mean of the similarity between the media sources in the given media set and the given pole media set
sub get_similarity_mean
{
    my ( $db, $topic, $media_sets, $pole_media_set_name ) = @_;

    my $pole_query = get_media_sets_query( $db, $topic, $pole_media_set_name );

    my $media_sets_ids_list = join( ',', map { $_->{ media_sets_id } } @{ $media_sets } );

    my ( $similarity_mean ) = $db->query(
        "select avg( mcmps.similarity ) " . "  from media_cluster_map_pole_similarities mcmps,media_sets_media_map msmm " .
          "  where mcmps.media_id = msmm.media_id and msmm.media_sets_id in (${ media_sets_ids_list }) " .
          "    and mcmps.queries_id = ? ",
        $pole_query->{ queries_id }
    )->flat;

    return $similarity_mean;
}

# get the stddev of the similarity between the media sources in the given media set and the given pole media set
sub get_similarity_stddev
{
    my ( $db, $topic, $media_sets, $pole_media_set_name ) = @_;

    my $pole_query = get_media_sets_query( $db, $topic, $pole_media_set_name );

    my $media_sets_ids_list = join( ',', map { $_->{ media_sets_id } } @{ $media_sets } );

    my ( $similarity_stddev ) = $db->query(
        "select stddev( mcmps.similarity ) " .
          "  from media_cluster_map_pole_similarities mcmps,media_sets_media_map msmm " .
          "  where mcmps.media_id = msmm.media_id and msmm.media_sets_id in (${ media_sets_ids_list }) " .
          "    and mcmps.queries_id = ? ",
        $pole_query->{ queries_id }
    )->flat;

    return $similarity_stddev;
}

# get the skewness of the similarity between the media sources in the given media set and the given pole media set
sub get_similarity_skewness
{
    my ( $db, $topic, $media_sets, $pole_media_set_name ) = @_;

    my $pole_query = get_media_sets_query( $db, $topic, $pole_media_set_name );

    my $media_sets_ids_list = join( ',', map { $_->{ media_sets_id } } @{ $media_sets } );

    my $sims = $db->query(
        "select mcmps.similarity " . "  from media_cluster_map_pole_similarities mcmps,media_sets_media_map msmm " .
          "  where mcmps.media_id = msmm.media_id and msmm.media_sets_id in (${ media_sets_ids_list }) " .
          "    and mcmps.queries_id = ? ",
        $pole_query->{ queries_id }
    )->flat;

    # below is mostly copied from Statistics::Descriptive
    my $n = @{ $sims };

    return 0 if ( $n < 3 );

    my $sd = get_similarity_stddev( $db, $topic, $media_sets, $pole_media_set_name );

    return 0 if ( !$sd );

    my $mean = get_similarity_mean( $db, $topic, $media_sets, $pole_media_set_name );

    my $sum_pow3;

    foreach my $sim ( @{ $sims } )
    {
        my $value = ( ( $sim - $mean ) / $sd );
        $sum_pow3 += $value**3;
    }

    my $correction = $n / ( ( $n - 1 ) * ( $n - 2 ) );

    my $skew = $correction * $sum_pow3;

    return $skew;
}

# get the kurtosis of the similarity between the media sources in the given media set and the given pole media set
sub get_similarity_kurtosis
{
    my ( $db, $topic, $media_sets, $pole_media_set_name ) = @_;

    my $pole_query = get_media_sets_query( $db, $topic, $pole_media_set_name );

    my $media_sets_ids_list = join( ',', map { $_->{ media_sets_id } } @{ $media_sets } );

    my $sims = $db->query(
        "select mcmps.similarity " . "  from media_cluster_map_pole_similarities mcmps,media_sets_media_map msmm " .
          "  where mcmps.media_id = msmm.media_id and msmm.media_sets_id in (${ media_sets_ids_list }) " .
          "    and mcmps.queries_id = ? ",
        $pole_query->{ queries_id }
    )->flat;

    # below is mostly copied from Statistics::Descriptive
    my $n = @{ $sims };

    return 0 if ( $n < 4 );

    my $sd = get_similarity_stddev( $db, $topic, $media_sets, $pole_media_set_name );

    return 0 if ( !$sd );

    my $mean = get_similarity_mean( $db, $topic, $media_sets, $pole_media_set_name );

    my $sum_pow4;
    foreach my $sim ( @{ $sims } )
    {
        $sum_pow4 += ( ( $sim - $mean ) / $sd )**4;
    }

    my $correction1 = ( $n * ( $n + 1 ) ) / ( ( $n - 1 ) * ( $n - 2 ) * ( $n - 3 ) );
    my $correction2 = ( 3 * ( $n - 1 )**2 ) / ( ( $n - 2 ) * ( $n - 3 ) );

    my $kurt = ( $correction1 * $sum_pow4 ) - $correction2;

    return $kurt;
}

# execute the functions in the given list with given params, optionally appending $label to the topic as the row header.
# assign result of each function run to the results hash, with ${ label }_${ function_name } as the key in the hash.
sub execute_functions
{
    my ( $functions, $results, $db, $topic, $label, @params ) = @_;

    for my $function ( @{ $functions } )
    {
        my ( $name, $func ) = @{ $function };

        my $full_label = $label ? "${ label }_${ name }" : $name;

        add_row_header( $full_label );

        $results->{ $full_label } = $func->( $db, $topic, @params );
    }
}

# for a given topic, execute the functions defined as statics at the top of the module on
# each of the relevant combinations for the given topic.  return a hash of results
# with the appropriate combination + the function name as the key and the
# result as the value.  eg:
# { 'term_freq' => $val, 'blogs_msm_comparison_word_cloud' => $val, ... }
sub get_topic_results
{
    my ( $db, $topic_name ) = @_;

    print STDERR "processing topic $topic_name ...\n";

    my $topic = $db->query( "select * from dashboard_topics where name = ?", $topic_name )->hash
      || die( "Unable to find topic '$topic_name'" );

    my $results = {};

    execute_functions( $_global_functions, $results, $db, $topic );

    for my $pole_media_set ( @{ $_pole_media_sets } )
    {
        execute_functions(
            $_pole_functions, $results, $db, $topic,
            $pole_media_set->{ nickname },
            $pole_media_set->{ nickname }
        );
    }

    my $media_set_groups = get_all_media_sets_as_groups();
    for my $media_set_group ( @{ $media_set_groups } )
    {
        execute_functions(
            $_media_set_functions, $results, $db, $topic,
            $media_set_group->{ nickname },
            $media_set_group->{ media_sets }
        );

        for my $pole_media_set ( @{ $_pole_media_sets } )
        {
            my $label = "$media_set_group->{ nickname }_$pole_media_set->{ nickname }_pole";
            execute_functions(
                $_media_set_pole_functions, $results, $db, $topic, $label,
                $media_set_group->{ media_sets },
                $pole_media_set->{ nickname }
            );
        }
    }

    my $media_set_pairs = get_media_set_comparison_pairs();
    for my $media_set_pair ( @{ $media_set_pairs } )
    {
        execute_functions(
            $_comparison_functions, $results, $db, $topic,
            $media_set_pair->{ nickname },
            $media_set_pair->{ a },
            $media_set_pair->{ b }
        );
    }

    return $results;
}

# get all row headers from $_row_header_order, sorted by the values of the hash
sub get_ordered_row_headers
{
    my $headers = [];

    while ( my ( $header, $order ) = each( %{ $_row_header_order } ) )
    {
        $headers->[ $order - 1 ] = $header;
    }

    return $headers;
}

# given a hash with topic names as values and a hash of functions/media_sets as values, return
# an encoded csv with topics as columns and function/media_sets as rows
sub convert_results_to_encoded_csv
{
    my ( $topic_results ) = @_;

    my $csv_hashes = [];

    my $query_labels = get_ordered_row_headers();

    for ( my $i = 0 ; $i < @{ $query_labels } ; $i++ )
    {
        my $query_label = $query_labels->[ $i ];
        $csv_hashes->[ $i ]->{ value } = $query_label;
        for my $topic_name ( @{ $_topic_names } )
        {
            $csv_hashes->[ $i ]->{ $topic_name } = $topic_results->{ $topic_name }->{ $query_label };
        }
    }

    my $fields = $_topic_names;
    unshift( @{ $fields }, 'value' );

    return MediaWords::Util::CSV::get_hashes_as_encoded_csv( $csv_hashes, $fields );
}

sub _set_config
{

    #my ( $static, $params, $name ) = @_;

    die( "param '$_[2]' is undef" ) if ( !defined( $_[ 1 ]->{ $_[ 2 ] } ) );

    $_[ 0 ] = $_[ 1 ]->{ $_[ 2 ] };
}

# given the params as formatted below and return the results of the functions as formatted below.
#
#
# The $params parameter must include each of the keys below, or the call will die.
# params:
# {
#    base_url => 'http://amanda.law.harvard.edu/admin'
#
#    media_sets =>
#      [ { name => 'Russian Top 25 Mainstream Media', nickname => 'msm', compare => 1 },
#        { name => 'Russian Government', nickname => 'gov', compare => 1 },
#        { name => 'Russian TV', nickname => 'tv', compare => 1 },
#        { name => 'Politics: Ethno-Nationalists', nickname => 'ethno', media_sets_id => 16712 },
#        { name => 'Politics: Democratic Opposition', nickname => 'dem', media_sets_id => 16715 } ],
#
#    media_set_groups =>
#      [ { nickname => 'blogs', media_set_nicknames => [ 'ethno', 'dem' ], compare => 1 } ],
#
#    topic_names =>
#      [ 'Protest (miting) (full)',
#        'Modernization (Full)',
#        'Buckets (Full)',
#        'Kashin (Full)',
#        'Putin (Full)',
#      ],
#
#    topic_dates =>
#      { 'Egypt (Full)' => [ '2011-01-01', '2011-03-01' ],
#        'Seliger (Full)' => [ '2011-06-01', '2011-09-01' ],
#        'anti-seliger (Full)' => [ '2011-06-01', '2011-09-01' ],
#        'Protest (miting) (full)' => [ '2011-12-01', '2012-01-01' ]
#        'Protest (Full)' => [ '2011-12-01', '2012-01-01' ]
#      },
#
#    pole_media_sets =>
#      [ { nickname => 'gov' },
#        { nickname => 'msm' } ,
#      ],
#
#    default_topic_dates =>
#      [ '2010-12-01', '2011-12-01' ]
#  }
#
# returns:
#
#  {
#    'putin' =>
#      {
#        'term_freq_blogs' => 'http://base_url/term/freq/blogs',
#        'overall_query_blogs' => 'http://base_url/query/blogs',
#      }
#  }
sub get_results
{
    my ( $db, $params ) = @_;

    _set_config( $_base_url,            $params, 'base_url' );
    _set_config( $_media_sets,          $params, 'media_sets' );
    _set_config( $_media_set_groups,    $params, 'media_set_groups' );
    _set_config( $_pole_media_sets,     $params, 'pole_media_sets' );
    _set_config( $_topic_names,         $params, 'topic_names' );
    _set_config( $_topic_dates,         $params, 'topic_dates' );
    _set_config( $_default_topic_dates, $params, 'default_topic_dates' );

    fetch_media_sets( $db );

    my $topic_results = {};

    for my $topic_name ( @{ $_topic_names } )
    {
        my $results = get_topic_results( $db, $topic_name );
        $topic_results->{ $topic_name } = $results;
    }

    return $topic_results;
}

# given params as documented for get_results above, return the results as a hash
sub get_results_as_encoded_csv
{
    my ( $db, $params ) = @_;

    my $topic_results = get_results( $db, $params );

    return convert_results_to_encoded_csv( $topic_results );
}
