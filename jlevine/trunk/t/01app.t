use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
}

use warnings;
use Test::More tests => 2;

use Catalyst::Test;

BEGIN { use_ok 'Catalyst::Test', 'MediaWords' }

action_redirect( '/', 'Request should succeed' );
