#!/usr/bin/env perl

# test that MediaWords::Test::Supervisor works as expected

use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::Test::Supervisor;

my $_test_supervisor_called;

sub test_supervisor
{
    $_test_supervisor_called = 1;

    # using goofy ps list as a way to check for running processes that doesn't use supervisor
    my $ps_list = `ps aux`;
    my @processes_to_test = ( qr/ExtractAndVector/, qr/MineTopic/, qr/beam.*rabbitmq/, qr/java.*solr/, );
    for my $process_regex ( @processes_to_test )
    {
        like( $ps_list, $process_regex, "process match: $process_regex" );
    }
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_supervisor,
        [ qw/extract_and_vector topic_mine job_broker:rabbitmq solr_standalone/ ] );

    ok( $_test_supervisor_called, "test_supervisor() called" );

    # second call to test_with_supervisor implicitly tests capability to wait for shutdown, which takes a few seconds
    eval {
        MediaWords::Test::Supervisor::test_with_supervisor( sub { }, [ 'bogus_process' ] );
    };
    ok( $@ && ( $@ =~ /no such process/ ), "unknown process detected: $@" );

    eval {
        MediaWords::Test::Supervisor::test_with_supervisor( sub { die( 'foo' ) }, [] );
    };
    ok( $@ && ( $@ =~ /error running supervisor test/ ), "error thrown from test" );

    done_testing();
}

main();
