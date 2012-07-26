use strict;
use warnings;
use Test::NoWarnings;
use Test::More tests => 2+1;

BEGIN { use_ok 'Catalyst::Test', 'MediaWords' }
BEGIN { use_ok 'MediaWords::Controller::Cosines' }

#action_ok( '/cosines', 'Request should succeed' );

