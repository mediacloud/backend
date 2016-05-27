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

sub test_status_ok
{
    my @paths = qw(
      /api/v2/topics/1/story/1
      /api/v2/topics/1/story/1/inlinks
      /api/v2/topics/1/story/1/outlinks
    );
    foreach my $url ( @paths )
    {
        my $base_url = { path => $url };
        my $response = MediaWords::Test::API::call_test_api( $base_url );
        Test::More::ok( $response->is_success, "Request should succeed: $url" );
    }
}

sub main
{
    test_status_ok();
    done_testing();
}

main();
