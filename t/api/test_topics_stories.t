#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin";
    use lib "$FindBin::Bin/../../lib";
    use Catalyst::Test 'MediaWords';

}

use Data::Dumper;
use MediaWords;
use MediaWords::Test::DB;
use MediaWords::Test::API;
use Readonly;

# This should match the DEFAULT_STORY_LIMIT in Stories.pm
Readonly my $DEFAULT_STORY_LIMIT => 10;

# A constant used to generate consistent orderings in test sorts
Readonly my $TEST_MODULO => 6;

sub _get_story_link_counts
{
    my $data = shift;

    # umber of prime factors outside the media source
    my $counts = {
        1  => 0,
        2  => 0,
        3  => 0,
        4  => 0,
        5  => 0,
        7  => 0,
        8  => 1,
        9  => 1,
        10 => 2,
        11 => 0,
        13 => 0,
        14 => 2,
        15 => 0
    };

    my %return_counts = map { "story " . $_ => $counts->{ $_ } } keys %{ $counts };
    return \%return_counts;

}

sub _get_expected_bitly_link_counts
{
    my $return_counts = {};

    foreach my $m ( 1 .. 15 )
    {

        if ( $m % $TEST_MODULO )
        {

            $return_counts->{ "story " . $m } = $m % ( $TEST_MODULO - 1 );
        }

    }
    return $return_counts;

}

sub test_status_ok
{
    my @paths = qw(
      /api/v2/topics/1/stories/list
      /api/v2/topics/1/stories/count
    );
    foreach my $url ( @paths )
    {
        my $base_url = { path => $url };
        my $response = MediaWords::Test::API::call_test_api( $base_url );
        Test::More::ok( $response->is_success, 'Request should succeed' );
    }
}

sub test_story_count
{

    # The number of stories returned in stories/list matches the count in cdts

    my $base_url = { path => '/api/v2/topics/1/stories/list' };

    my $response = MediaWords::Test::API::call_test_api( $base_url );

    Test::More::ok( $response->is_success, 'Request should succeed' );

    my $actual_response = JSON::decode_json( $response->decoded_content() );

    Test::More::ok( scalar @{ $actual_response->{ stories } } == $DEFAULT_STORY_LIMIT );

}

sub test_default_sort
{

    my $data = shift;

    my $base_url = { path => '/api/v2/topics/1/stories/list?limit=20' };

    my $sort_key = "inlink_count";

    my $expected_counts = _get_story_link_counts( $data );

    _test_sort( $data, $expected_counts, $base_url, $sort_key );

}

sub test_social_sort
{

    my $data = shift;

    my $base_url = { path => '/api/v2/topics/1/stories/list?sort=social&limit=20' };

    my $sort_key = "bitly_click_count";

    my $expected_counts = _get_expected_bitly_link_counts();

    _test_sort( $data, $expected_counts, $base_url, $sort_key );

}

sub _test_sort
{

    # Make sure that only expected stories are in stories list response
    # in the appropriate order

    my ( $data, $expected_counts, $base_url, $sort_key ) = @_;

    my $response = MediaWords::Test::API::call_test_api( $base_url );

    my $actual_response = JSON::decode_json( $response->decoded_content() );

    my $actual_stories_inlink_counts = {};
    my $actual_stories_order         = ();

    foreach my $story ( @{ $actual_response->{ stories } } )
    {
        $actual_stories_inlink_counts->{ $story->{ 'title' } } = $story->{ $sort_key };
        my @story_info = ( $story->{ $sort_key }, $story->{ 'stories_id' } );
        push @{ $actual_stories_order }, \@story_info;
    }

    is_deeply( $actual_stories_inlink_counts, $expected_counts, 'expected stories' );

    foreach my $story ( 1 .. scalar @{ $actual_stories_order } - 1 )
    {
        ok( $actual_stories_order->[ $story ]->[ 0 ] <= $actual_stories_order->[ $story - 1 ]->[ 0 ] );
        if ( $actual_stories_order->[ $story ]->[ 0 ] == $actual_stories_order->[ $story - 1 ]->[ 0 ] )
        {
            ok( $actual_stories_order->[ $story ]->[ 1 ] > $actual_stories_order->[ $story - 1 ]->[ 1 ] );
        }
    }
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {

            my $db = shift;
            MediaWords::Test::API::create_test_api_user( $db );

            my $stories = {
                A => {
                    B => [ 1, 2, 3 ],
                    C => [ 4, 5, 6, 15 ]
                },
                D => { E => [ 7, 8, 9 ] },
                F => {
                    G => [ 10, ],
                    H => [ 11, 12, 13, 14, ]
                }
            };

            my $controversy_media = MediaWords::Test::API::create_stories( $db, $stories );

            MediaWords::Test::API::create_test_data( $db, $controversy_media );

            test_status_ok();
            test_story_count();
            test_default_sort( $stories );
            test_social_sort( $stories );
            done_testing();
        }
    );
}

main();
