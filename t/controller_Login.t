use strict;
use warnings;
use Test::More;

BEGIN
{
    $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;
    use_ok 'Catalyst::Test', 'MediaWords';
}
use MediaWords::Controller::Login;

ok( request( '/login' )->is_success, 'Request should succeed' );
done_testing();
