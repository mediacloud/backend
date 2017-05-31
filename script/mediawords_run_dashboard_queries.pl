#!/usr/bin/env perl

# Make calls to solr api that simulate the generation of a dashboard page.
# By default run the first topic queries by topics_id with solr queries.
#
# usage: mediawords_run_dashboard_queries [ < query >, < query >, ... ]

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Catalyst::Test 'MediaWords';
use Encode;
use URI;

use MediaWords::DB;
use MediaWords::Util::JSON;

my $_key;

# create url from relative path + query params and call Catalyst::Test::get() on that url.  get the $data structure
# generated from the resulting json.  invoke the $test function with the resulting $data and die if that
# test function returns false.
sub test_url
{
    my ( $path, $params, $test ) = @_;

    $params->{ key } = $_key;

    my $url = URI::new();
    $url->query_form( $params );
    $url->path( $path );

    DEBUG( "requesting url: $url" );

    my $content = get( $url->as_string );

    my $data;
    eval { $data = MediaWords::Util::JSON::decode_json( $content ); };
    die( "json decode error on { $content }: $@" ) if ( $@ );

    die( "failed test for $path / $params->{ q }" ) unless ( $test->( $data ) );
}

# run the dashboard queries required
sub run_dashboard_queries
{
    my ( $topic ) = @_;

    my $query      = $topic->{ solr_seed_query };
    my $start_date = substr( $topic->{ start_date }, 0, 10 );
    my $end_date   = substr( $topic->{ end_date }, 0, 10 );

    my $start_time = time;

    test_url(
        '/api/v2/sentences/list',
        { q => $query, rows => 10, sort => 'random' },
        sub { @{ $_[ 0 ]->{ response }->{ docs } } > 0 }
    );

    test_url( '/api/v2/sentences/count', { q => $query }, sub { $_[ 0 ]->{ count } > 0 } );
    test_url( '/api/v2/stories/count',   { q => $query }, sub { $_[ 0 ]->{ count } > 0 } );

    test_url(
        '/api/v2/sentences/count',
        { q => $query, split => 1, split_start_date => $start_date, split_end_date => $end_date },
        sub { ( $_[ 0 ]->{ count } > 0 ) && $_[ 0 ]->{ split } }
    );

    test_url( '/api/v2/wc/list', { q => $query }, sub { $_[ 0 ]->[ 0 ]->{ count } > 0 } );

    test_url( '/api/v2/sentences/field_count', { q => $query }, sub { $_[ 0 ]->[ 0 ]->{ count } > 0 } );

    DEBUG( "elapsed time for '$query': " . ( time - $start_time ) );
}

sub main
{
    my $topics;

    my $db = MediaWords::DB::connect_to_db;

    if ( @ARGV )
    {
        my $end_date = MediaWords::Util::SQL::sql_now;
        $topics = [ map { { solr_seed_query => $_, start_date => '2010-01-01', end_date => $end_date } } @ARGV ];
    }
    else
    {
        $topics = $db->query( <<SQL )->hashes;
select solr_seed_query, start_date, end_date
    from topics
    order by topics_id desc
    limit 10;
SQL
    }

    my $key = $db->query( <<SQL )->flat;
select api_key
    from auth_users
        join auth_users_roles_map using ( auth_users_id )
        join auth_roles using ( auth_roles_id )
    where
        role in ( 'admin-readonly', 'admin' )
    limit 1
SQL
    die( "Unable to find admin api_key in auth_users" ) unless ( $key );

    $_key = $key;

    my $start_time = time;

    for my $topic ( @{ $topics } )
    {
        run_dashboard_queries( $topic );
    }

    DEBUG( "total elapsed time: " . ( time - $start_time ) );

}

main();
