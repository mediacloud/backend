use strict;

use warnings;
use Test::NoWarnings;
use Test::More tests => 2 + 1;

use MediaWords::Test::DB::Environment;

BEGIN
{
    MediaWords::Test::DB::Environment::force_using_test_database();
    use_ok 'Catalyst::Test', 'MediaWords';
}

action_redirect( '/status', 'Request should succeed' );
