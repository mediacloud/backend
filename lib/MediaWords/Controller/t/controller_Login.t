use strict;
use warnings;
use Test::More tests => 2;

use MediaWords::Test::DB::Environment;

BEGIN
{
    MediaWords::Test::DB::Environment::force_using_test_database();
    use_ok 'Catalyst::Test', 'MediaWords';
}
use MediaWords::Controller::Login;

# Catalyst::Test::request()
ok( request( '/login' )->is_success, 'Request should succeed' );
