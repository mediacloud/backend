use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 11;

use DateTime;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::DateTime' );
}

sub test_gmt_datetime_from_timestamp()
{
    my $timestamp;
    my $datetime;
    my $datetime_2;

    # Start of epoch
    $timestamp = 0;
    $datetime  = gmt_datetime_from_timestamp( $timestamp );
    isa_ok( $datetime, 'DateTime' );
    is( DateTime->compare( $datetime, DateTime->from_epoch( epoch => 0 ) ), 0 );

    # Some other date
    $datetime_2 = DateTime->new(
        year      => 1969,
        month     => 7,
        day       => 24,
        hour      => 16,
        minute    => 50,
        second    => 35,
        time_zone => 'UTC'
    );
    $timestamp = $datetime_2->epoch;
    $datetime  = gmt_datetime_from_timestamp( $timestamp );
    isa_ok( $datetime, 'DateTime' );
    is( DateTime->compare( $datetime, $datetime_2 ), 0 );

    # Some other timezone
    $timestamp = DateTime->new(
        year      => 1990,
        month     => 3,
        day       => 11,
        hour      => 12,
        minute    => 0,
        second    => 0,
        time_zone => 'Europe/Vilnius'
    )->epoch;

    $datetime_2 = DateTime->new(    # same date, different TZ
        year      => 1990,
        month     => 3,
        day       => 11,
        hour      => 9,
        minute    => 0,
        second    => 0,
        time_zone => 'GMT'
    );
    $datetime = gmt_datetime_from_timestamp( $timestamp );
    isa_ok( $datetime, 'DateTime' );
    is( DateTime->compare( $datetime, $datetime_2 ), 0 );
}

sub test_gmt_date_string_from_timestamp()
{
    is( gmt_date_string_from_timestamp( 0 ),         '1970-01-01T00:00:00' );
    is( gmt_date_string_from_timestamp( -13849765 ), '1969-07-24T16:50:35' );
    is( gmt_date_string_from_timestamp( 637146000 ), '1990-03-11T09:00:00' );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_gmt_datetime_from_timestamp();
    test_gmt_date_string_from_timestamp();
}

main();
