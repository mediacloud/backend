use strict;

use List::Util;
use warnings;

BEGIN
{
    use_ok( 'MediaWords::DB' );
    use_ok( 'MediaWords::DBI::Queries' );
}

use Test::More tests => 416;
# create some media sets, dashboards, and dashboard_topics to use for query creation
sub create_query_parts
{
    my ( $db ) = @_;

    my $tag_set = $db->create( 'tag_sets', { name => 'qs test' } );
    my $tag = $db->create( 'tags', { tag => 'qs test', tag_sets_id => $tag_set->{ tag_sets_id } } );

    my $media_sets;
    for my $i ( 1 .. 4 )
    {
        my $media_set =
          $db->create( 'media_sets', { name => "qs test $i", set_type => 'collection', tags_id => $tag->{ tags_id } } );
        push( @{ $media_sets }, $media_set );
    }

    my $dashboards = [];
    for my $i ( 1 .. 4 )
    {
        my $dashboard =
          $db->create( 'dashboards', { name => "qs test $i", start_date => '2010-01-01', end_date => '2020-01-01' } );

        for my $j ( 1 .. 4 )
        {
            my $dashboard_topic = $db->create(
                'dashboard_topics',
                {
                    name          => "qs test $i topic $j",
                    query         => "foo",
                    dashboards_id => $dashboard->{ dashboards_id },
                    start_date    => '2010-01-01',
                    end_date      => '2020-01-01',
                    language      => 'en'
                }
            );
            push( @{ $dashboard->{ dashboard_topics } }, $dashboard_topic );
        }

        for my $j ( 1 .. $i )
        {
            $db->create(
                'dashboard_media_sets',
                {
                    dashboards_id => $dashboard->{ dashboards_id },
                    media_sets_id => $media_sets->[ $j - 1 ]->{ media_sets_id }
                }
            );
        }

        push( @{ $dashboards }, $dashboard );
    }

    return ( $media_sets, $dashboards );
}

# add a name and a set of params that define each test
sub add_test
{
    my ( $tests, $name, $start_date, $end_date, $media_sets, $dashboard_topics, $dashboard ) = @_;

    my $test_name = "$name [ $start_date - $end_date ]";

    # print STDERR "add test: $test_name\n";

    $media_sets       = [ $media_sets ]       if ( $media_sets       && ( ref( $media_sets ) ne 'ARRAY' ) );
    $dashboard_topics = [ $dashboard_topics ] if ( $dashboard_topics && ( ref( $dashboard_topics ) ne 'ARRAY' ) );

    my $params = {
        media_sets_ids       => [ map { $_->{ media_sets_id } } @{ $media_sets } ],
        dashboards_id        => $dashboard->{ dashboards_id },
        dashboard_topics_ids => [ map { $_->{ dashboard_topics_id } } @{ $dashboard_topics } ],
        start_date           => $start_date,
        end_date             => $end_date
    };

    push( @{ $tests }, { name => $test_name, params => $params } );
}

# test signature code by creating various configurations of queries and making sure
# we always get the same query back the second time we run find_or_create_query_by_params with the same params
sub test_query_signatures
{
    my ( $db, $media_sets, $dashboards ) = @_;

    my $tests = [];

    my $dates = [ '2010-01-01', '2011-01-01', '2012-01-01' ];

    my $dashboard_topics = $dashboards->[ 0 ]->{ dashboard_topics };

    for my $sd ( @{ $dates } )
    {
        for my $ed ( @{ $dates } )
        {
            for my $ms ( @{ $media_sets } )
            {
                add_test( $tests, '1 ms', $sd, $ed, $ms );

                for my $dt ( @{ $dashboard_topics } )
                {
                    add_test( $tests, '1 ms 1 dt', $sd, $ed, $ms, $dt );
                }

                add_test( $tests, '1 ms all t', $sd, $ed, $ms, $dashboard_topics );
            }

            add_test( $tests, 'all ms', $sd, $ed, $media_sets );

            add_test( $tests, 'all ms all dt', $sd, $ed, $media_sets, $dashboard_topics );

            for my $d ( @{ $dashboards } )
            {
                add_test( $tests, '1 d', $sd, $ed, undef, undef, $d );

                for my $dt ( @{ $dashboard_topics } )
                {
                    add_test( $tests, '1 d 1 dt', $sd, $ed, undef, $dt, $d );
                }
            }
        }
    }

    map { $_->{ create_query } = MediaWords::DBI::Queries::find_or_create_query_by_params( $db, $_->{ params } ) }
      @{ $tests };

    my $tests = [ List::Util::shuffle( @{ $tests } ) ];

    for my $test ( @{ $tests } )
    {
        my $found_query = MediaWords::DBI::Queries::find_or_create_query_by_params( $db, $test->{ params } );
        is( $test->{ create_query }->{ queries_id }, $found_query->{ queries_id }, $test->{ name } );
    }

    return scalar( @{ $tests } );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    $db->begin;

    my $num_tests;
    eval {
        my ( $media_sets, $dashboards ) = create_query_parts( $db );
        $num_tests = test_query_signatures( $db, $media_sets, $dashboards );
    };

    die( $@ ) if ( $@ );

    $db->rollback;

}

main();
