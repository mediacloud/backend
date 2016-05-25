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

sub test_media_list
{
    my $data = shift;

    my $base_url = { path => '/api/v2/topics/1/media/list' };

    my $response = MediaWords::Test::API::call_test_api( $base_url );

    Test::More::ok( $response->is_success, 'Request should succeed' );

    my $actual_response = JSON::decode_json( $response->decoded_content() );

    ok( scalar @{ $actual_response->{ media } } == 3,
        "returned unexpected number of media scalar $actual_response->{ media }" );

    # Check descending link count
    foreach my $m ( 1 .. $#{ $actual_response->{ media } } )
    {
        ok( $actual_response->{ media }[ $m ]->{ inlink_count } <= $actual_response->{ media }[ $m - 1 ]->{ inlink_count } );
    }

    # Check that we have right number of inlink counts for each media source

    my $inlink_counts = { F => 4, D => 2, A => 0 };

    foreach my $mediasource ( @{ $actual_response->{ media } } )
    {
        ok( $mediasource->{ inlink_count } == $inlink_counts->{ $mediasource->{ name } } );
    }
}

sub test_media_single
{

    my $data = shift;

    my $base_url = { path => '/api/v2/topics/1/media/1' };

    my $response = MediaWords::Test::API::call_test_api( $base_url );

    Test::More::ok( $response->is_success, 'Request should succeed' );

    my $actual_response = JSON::decode_json( $response->decoded_content() );

    ok( $actual_response->{ media }, 'Response should have media block' );

    ok( $actual_response->{ tags }, 'Response should have tags block' );

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

            test_media_list( $stories );
            test_media_single( $stories );

            # TODO: populate stories for testing
            # test_endpoint_exists();
            # test_required_parameters();
            done_testing();
        }
    );
}

main();
