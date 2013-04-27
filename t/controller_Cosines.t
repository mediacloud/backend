use strict;
use warnings;
use Test::NoWarnings;
use Test::More tests => 2 + 1;

BEGIN
{
    $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;
    use_ok 'Catalyst::Test', 'MediaWords';
}
BEGIN { use_ok 'MediaWords::Controller::Admin::Cosines' }

#action_ok( '/admin/cosines', 'Request should succeed' );

