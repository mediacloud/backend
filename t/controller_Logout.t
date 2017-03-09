use strict;
use warnings;
use Test::More tests => 1;

use MediaWords::Test::DB;

BEGIN
{
    MediaWords::Test::DB::force_using_test_database();
    use_ok 'Catalyst::Test', 'MediaWords';
}
use MediaWords::Controller::Logout;

# Commented out because we need to log in first
# Catalyst::Test::request()
#ok( request( '/logout' )->is_success, 'Request should succeed' );
