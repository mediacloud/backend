use strict;

use warnings;
use Test::NoWarnings;
use Test::More tests => 2 + 1;

use MediaWords::Test::DB;

BEGIN
{
    MediaWords::Test::DB::force_using_test_database();
    use_ok 'Catalyst::Test', 'MediaWords';
}

action_redirect( '/', 'Request should succeed' );
