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

sub test_endpoint_exists
{
    my $base_url = { path => '/api/v2/topics/1/sentence/count', params => { q => 'sentence:Obama' } };
    my $response = MediaWords::Test::API::call_test_api( $base_url );
    Test::More::ok( $response->is_success, 'Request should succeed' );
}

sub test_required_parameters
{
    my $base_url = { path => '/api/v2/topics/1/sentence/count' };
    my $response = MediaWords::Test::API::call_test_api( $base_url );
    Test::More::ok( $response->is_error, 'Request should fail without required parameters' );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;
            MediaWords::Test::API::create_test_api_user( $db );
            test_endpoint_exists();
            test_required_parameters();
            done_testing();
        }
    );
}

main();
