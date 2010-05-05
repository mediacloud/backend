use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok 'Catalyst::Test', 'MediaWords' }
BEGIN { use_ok 'MediaWords::Controller::Feeds' }

ok( request('/feeds')->is_success, 'Request should succeed' );


