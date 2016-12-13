use strict;
use warnings;
use Test::More tests => 1;

BEGIN
{
    $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;
    use_ok 'Catalyst::Test', 'MediaWords';
}
use MediaWords::Controller::Logout;

# Commented out because we need to log in first
#ok( request( '/logout' )->is_success, 'Request should succeed' );
