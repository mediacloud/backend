use strict;
use warnings;
use Test::More;

#Comment out since tests are usually skipped
#use Test::NoWarnings;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => 'Test::Pod::Coverage 1.04 required' if $@;
plan skip_all => 'set TEST_POD to enable this test' unless $ENV{ TEST_POD };

all_pod_coverage_ok();
