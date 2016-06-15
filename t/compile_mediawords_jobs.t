use strict;
use warnings;

use Test::Strict;
use Test::NoWarnings;

$Test::Strict::TEST_WARNINGS = 1;

all_perl_files_ok( 'lib/MediaWords/Job' );
