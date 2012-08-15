use strict;
use warnings;
use Test::More;

#Commenting out test no warnings because all tests are skipped
#use Test::NoWarnings;

eval "use Test::Pod 1.14";
plan skip_all => 'Test::Pod 1.14 required' if $@;

my $run_tests = $ENV{ TEST_POD };

plan skip_all => 'set TEST_POD to enable this test' unless $run_tests;

all_pod_files_ok();
