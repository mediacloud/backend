#!/usr/bin/env perl

use strict;
use warnings;
use Modern::Perl "2015";

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More tests => 8;
use Test::NoWarnings;

use Data::Dumper;
use Readonly;
use Storable qw/dclone/;

use MediaWords::Test::DB;

Readonly my $normal_work_mem => 256;    # MB
Readonly my $large_work_mem  => 512;    # MB

sub test_execute_with_large_work_mem($)
{
    my $db = shift;

    my $config             = MediaWords::Util::Config::get_config();
    my $new_config         = dclone( $config );
    my $old_large_work_mem = $new_config->{ mediawords }->{ large_work_mem };
    delete $new_config->{ mediawords }->{ large_work_mem };
    $new_config->{ mediawords }->{ large_work_mem } = $large_work_mem . 'MB';
    MediaWords::Util::Config::set_config( $new_config );

    $db->query( 'SET work_mem = ?', $normal_work_mem . 'MB' );
    my ( $current_work_mem ) = $db->query( "SELECT setting::int FROM pg_settings WHERE name = 'work_mem'" )->flat;
    is( $current_work_mem, $normal_work_mem * 1024 );

    $db->query( 'CREATE TEMPORARY TABLE execute_large_work_mem (work_mem INT NOT NULL)' );
    $db->execute_with_large_work_mem(
        <<EOF
        INSERT INTO execute_large_work_mem (work_mem)
        SELECT setting::int FROM pg_settings WHERE name = 'work_mem'
EOF
    );
    ( my $number ) = $db->query( 'SELECT * FROM execute_large_work_mem' )->flat;
    is( $number, $large_work_mem * 1024 );

    ( $current_work_mem ) = $db->query( "SELECT setting::int FROM pg_settings WHERE name = 'work_mem'" )->flat;
    is( $current_work_mem, $normal_work_mem * 1024 );

    $config     = MediaWords::Util::Config::get_config();
    $new_config = dclone( $config );
    delete $new_config->{ mediawords }->{ large_work_mem };
    $new_config->{ mediawords }->{ large_work_mem } = $old_large_work_mem;
    MediaWords::Util::Config::set_config( $new_config );
}

sub test_run_block_with_large_work_mem($)
{
    my $db = shift;

    my $config             = MediaWords::Util::Config::get_config();
    my $new_config         = dclone( $config );
    my $old_large_work_mem = $new_config->{ mediawords }->{ large_work_mem };
    delete $new_config->{ mediawords }->{ large_work_mem };
    $new_config->{ mediawords }->{ large_work_mem } = $large_work_mem . 'MB';
    MediaWords::Util::Config::set_config( $new_config );

    $db->query( 'SET work_mem = ?', $normal_work_mem . 'MB' );
    my ( $current_work_mem ) = $db->query( "SELECT setting::int FROM pg_settings WHERE name = 'work_mem'" )->flat;
    is( $current_work_mem, $normal_work_mem * 1024 );

    $db->query( 'CREATE TEMPORARY TABLE run_large_work_mem (work_mem INT NOT NULL)' );
    $db->run_block_with_large_work_mem(
        sub {
            $db->query(
                <<EOF
            INSERT INTO run_large_work_mem (work_mem)
            SELECT setting::int FROM pg_settings WHERE name = 'work_mem'
EOF
            );
        }
    );
    ( my $number ) = $db->query( 'SELECT * FROM run_large_work_mem' )->flat;
    is( $number, $large_work_mem * 1024 );

    ( $current_work_mem ) = $db->query( "SELECT setting::int FROM pg_settings WHERE name = 'work_mem'" )->flat;
    is( $current_work_mem, $normal_work_mem * 1024 );

    $config     = MediaWords::Util::Config::get_config();
    $new_config = dclone( $config );
    delete $new_config->{ mediawords }->{ large_work_mem };
    $new_config->{ mediawords }->{ large_work_mem } = $old_large_work_mem;
    MediaWords::Util::Config::set_config( $new_config );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_execute_with_large_work_mem( $db );
            test_run_block_with_large_work_mem( $db );

            Test::NoWarnings::had_no_warnings();
        }
    );

}

main();

