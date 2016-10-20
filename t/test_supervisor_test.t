#!/usr/bin/env perl

# test that MediaWords::Test::Supervisor works as expected

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";

}

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::Test::Supervisor;

my $_test_supervisor_called;

sub test_supervisor
{
    DEBUG( "TEST_SUPERVISOR" );
    $_test_supervisor_called = 1;
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_supervisor,
        [ qw/extract_and_vector topic_mine job_broker:rabbitmq solr_standalone/ ] );

    ok( $_test_supervisor_called, "test_supervisor() called" );

    done_testing();
}

main();
