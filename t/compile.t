use strict;
use warnings;

# parallell ok

use Test::Strict;
use Test::NoWarnings;

$Test::Strict::TEST_WARNINGS = 1;

all_perl_files_ok( 'script', 'lib/MediaWords/GearmanFunction' );
