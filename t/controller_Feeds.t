use strict;
use warnings;
use Test::NoWarnings;
use Test::More tests => 2 + 1;

BEGIN
{
    $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;
    use_ok 'Catalyst::Test', 'MediaWords';
}
BEGIN { use_ok 'MediaWords::Controller::Admin::Feeds' }

# Commented out because we need to log in first
#ok( request( '/admin/feeds/list/1' )->is_success, 'Request should succeed' );

