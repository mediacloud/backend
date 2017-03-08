use strict;
use warnings;
use Test::More tests => 2;

use MediaWords::Test::DB;

BEGIN
{
    MediaWords::Test::DB::force_using_test_database();
    use_ok 'Catalyst::Test', 'MediaWords';
}
use MediaWords::Controller::Login;

ok( Catalyst::Test::request( '/login' )->is_success, 'Request should succeed' );
