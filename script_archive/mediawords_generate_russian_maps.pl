#!/usr/bin/perl

# generate a csv of urls of query based urls for the russia project.
# the columnns of the table are topics, and the rows are various
# query tool results for each topic

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::Cluster;
use MediaWords::Cluster::Map;
use MediaWords::DB;
use MediaWords::DBI::Queries;
use MediaWords::Util::CSV;

# base media cloud url
my $_base_url = 'http://amanda.law.harvard.edu/admin';

my $_russian_media_set_names =
    [ 'Russian Top 25 Mainstream Media',
      'Russian Government',
      'Russian TV',
      [ { name => 'Politics: Ethno-Nationalists', media_sets_id => 16712 }, 
        { name => 'Politics: Democratic Opposition', media_sets_id => 16715 } ] ];
        
my $_russian_media_sets;

my $_russian_topic_names =
    [ 'Protest (miting) (full)',
      'Modernization (Full)',
      'Buckets (Full)',
      'Kashin (Full)',
      'Putin (Full)',
      'Terrorist Act (Full)',
      'Tunisia (Full)',
      'Khimki (Full)',
      'Khodorkovsky (Full)',
      'Domodedovo (Full)',
      'Corruption (Full)',
      'Blue (Full)',
      'anti-seliger (Full)',
      'Kudrin (Full)',
      'Smog (Full)',
      'Riots (Full)',
      'Explosion (Full)',
      'Egypt (Full)',
      'Metro (Full)',
      'Seliger (Full)',
      'Protest (Full)',
      'Skolkovo (Full)',
      'Flashing Lights (Full)',
      'Terroist Act (Full)',
      'Nashi (Full)',
      'Fire (Full)',
      'Medvedev (Full)',
    ];
    
# topics with non default dates
my $_russian_topic_dates = 
    { 'Egypt (Full)' => [ '2011-01-01', '2011-03-01' ],
      'Seliger (Full)' => [ '2011-06-01', '2011-09-01' ],
      'anti-seliger (Full)' => [ '2011-06-01', '2011-09-01' ],
    };
    
# list of functions to use to generate cell values
my $_query_functions = 
    [
        [ 'overall_query', \&get_overall_query_url ],
        [ 'government_map', \&get_government_map_url ],
        [ 'msm_map', \&get_msm_map_url ],
        [ 'term_freq', \&get_term_freq_url ],
    ];

# turn a 2d matrix into a flat list
sub flatten 
{ 
    my ( $list ) = @_;
    
    my $flat = [];
    
    map { push( @{ $flat }, ( ref( $_ ) eq 'ARRAY' ) ? @{ $_ } : $_ ) } @{ $list };

    return $flat;
}

sub get_russian_media_sets
{
    my ( $db, $media_set_name ) = @_;
       
    if ( !ref( $media_set_name ) )
    {
        return $db->query( 'select * from media_sets where name = ?', $media_set_name )->hash ||
            die( "Unable to find media set '$media_set_name'" );
    }
    elsif ( ref ( $media_set_name ) eq 'HASH' )
    {
        return $db->query( 'select * from media_sets where media_sets_id = ?', $media_set_name->{ media_sets_id } )->hash ||
            die( "Unable to find media set $media_set_name->{ media_sets_id }" );
    }
    elsif ( ref( $media_set_name ) eq 'ARRAY' )
    {
        return [ map { get_russian_media_sets( $db, $_ ) } @{ $media_set_name } ];
    }
    else
    {
        die( "Unknown ref type: " . ref( $media_set_name ) );
    }
}

# return a list of all media sets ids in $_russian_media_sets
sub get_all_media_sets_ids
{
    my $all_media_sets = flatten( $_russian_media_sets );
        
    # print Dumper( $all_media_sets );
    
    return [ map { $_->{ media_sets_id } } @{ $all_media_sets } ];
}

# get teh start and end dates of the given topic, as determined by $_topic_dates
sub get_topic_dates
{
    my ( $topic ) = @_;
    
    my ( $start_date, $end_date );
    if ( my $dates = $_russian_topic_dates->{ $topic->{ name } } )
    {
        ( $start_date, $end_date ) = @{ $dates };
    }
    else 
    {
        ( $start_date, $end_date ) = ( '2010-12-01', '2011-12-01' );
    }
    
    return ( $start_date, $end_date );
}

# get the query corresponding to all media sets for the given topic
sub get_overall_query
{
    my ( $db, $topic ) = @_;
        
    my ( $start_date, $end_date ) = get_topic_dates( $topic );
    
    return MediaWords::DBI::Queries::find_or_create_query_by_params( $db, 
        { start_date => $start_date,
          end_date => $end_date,
          media_sets_ids => get_all_media_sets_ids( ),
          dashboard_topics_ids => [ $topic->{ dashboard_topics_id } ] } );    
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
    
    my $cluster_run = $db->query( 
        "select * from media_cluster_runs where clustering_engine = 'media_sets' and queries_id = ?", 
        $query->{ queries_id } )->hash;
        
    return $cluster_run if ( $cluster_run );

    $cluster_run = $db->create( 'media_cluster_runs', { 
        clustering_engine => 'media_sets',
		queries_id => $query->{ queries_id },
        num_clusters => scalar( @{ get_all_media_sets_ids() } ) } );

    my $clustering_engine = MediaWords::Cluster->new( $db, $cluster_run );

    $clustering_engine->execute_and_store_media_cluster_run();
    
    return $cluster_run;
}

# get query for the given topic and media set or sets
sub get_media_sets_query
{
    my ( $db, $topic, $media_sets ) = @_;
    
    my ( $start_date, $end_date ) = get_topic_dates( $topic );
    my $media_sets_ids = [ map { $_->{ media_sets_id } } @{ $media_sets } ];
        
    return MediaWords::DBI::Queries::find_or_create_query_by_params( $db, 
        { start_date => $start_date,
          end_date => $end_date,
          media_sets_ids => $media_sets_ids,
          dashboard_topics_ids => [ $topic->{ dashboard_topics_id } ] } );    

}

# return the media set with the given name
sub get_media_set
{
    my ( $db, $name ) = @_;
    
    return $db->query( "select * from media_sets where name = ?", $name )->hash ||
        die( "Unable to find media set '$name'" );
}

# get a polar query for the given topic with the media set of the given name at the pole
sub get_polar_map_url
{
    my ( $db, $topic, $polar_media_set_name ) = @_;

    my $cluster_run = find_or_create_cluster_run( $db, $topic );
    
    my $polar_query = get_media_sets_query( $db, $topic, [ get_media_set( $db, $polar_media_set_name ) ] );
    
    print Dumper( $cluster_run );
    print Dumper( $polar_query );
        
    my $cluster_map = MediaWords::Cluster::Map::generate_cluster_map( $db, $cluster_run, 'polar', [ $polar_query ], 0, 'graphviz-neato' );
    
    return "$_base_url/clusters/view/" . 
        $cluster_run->{ media_cluster_runs_id } . "?media_cluster_maps_id=" . $cluster_map->{ media_cluster_maps_id };
}

# get a polar map with the government as the pole
sub get_government_map_url 
{
    my ( $db, $topic ) = @_;

    return get_polar_map_url( $db, $topic, 'Russian Government' );
}

# get a polar map with the msm as the pole
sub get_msm_map_url 
{
    my ( $db, $topic ) = @_;
    
    return get_polar_map_url( $db, $topic, 'Russian Top 25 Mainstream Media' );
}

# get the term freq for the given term within the overall query
sub get_term_freq_url
{
    my ( $db, $topic ) = @_;
    
    my $query = get_overall_query( $db, $topic );
    
    my $esc_term = URI::Escape::uri_escape_utf8( $topic->{ query } );
    
    return "$_base_url/queries/terms/" . $query->{ queries_id } . "?terms=${ esc_term }";
}

# for a given topic, generate the various query urls
sub get_topic_query_urls
{
    my ( $db, $topic_name ) = @_;
    
    print STDERR "processing topic $topic_name ...\n";
    
    my $topic = $db->query( "select * from dashboard_topics where name = ?", $topic_name )->hash ||
        die( "Unable to find topic '$topic_name'" );
    
    my $query_urls = {};

    for my $query_function ( @{ $_query_functions } )
    {
        my ( $name, $func ) = @{ $query_function };
        print STDERR "$name ...\n";
        $query_urls->{ $name } = $func->( $db, $topic );
    }

    return $query_urls;
}

# print a csv with the topics as the column headers and the query values as the row headers
sub print_csv
{
    my ( $topic_urls ) = @_;
    
    my $csv_hashes = [];
    
    my $query_labels = [ keys( %{ $_query_functions } ) ];
    
    for ( my $i = 0; $i < @{ $query_labels }; $i++ )
    {
        my $query_label = $query_labels->[ $i ];
        $csv_hashes->[ $i ]->{ value } = $query_label;
        for my $topic_name ( @{ $_russian_topic_names } )
        {
            $csv_hashes->[ $i ]->{ $topic_name } = $topic_urls->{ $topic_name }->{ $query_label };
        }
    }
    
    print MediaWords::Util::CSV::get_hashes_as_encoded_csv( $csv_hashes, [ 'value', @{ $_russian_topic_names } ] );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;
    
    $_russian_media_sets = get_russian_media_sets( $db, $_russian_media_set_names );
    
    my $topic_urls = {};
    
    for my $topic_name ( @{ $_russian_topic_names } )
    {
        my $query_urls = get_topic_query_urls( $db, $topic_name );
        $topic_urls->{ $topic_name } = $query_urls;
    }
    
    # my $query_urls = invert_topic_urls( $topic_urls );
    
    print_csv( $topic_urls );
    
}

main();