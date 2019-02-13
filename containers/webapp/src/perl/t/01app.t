use strict;

use warnings;
use Test::NoWarnings;
use Test::More tests => 2 + 1;

BEGIN
{
    use_ok 'Catalyst::Test', 'MediaWords';
}

action_ok( '/status', 'Request should succeed' );
