#!/usr/bin/env prove

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use utf8;
use Test::NoWarnings;
use Test::More tests => 293;

use MediaWords::Util::DateTime;
use DateTime;
use Time::Local;

use_ok( 'MediaWords::Util::DateTime' );


sub test_local_timezone()
{
    my $local_tz = MediaWords::Util::DateTime::local_timezone();
    isa_ok( $local_tz, 'DateTime::TimeZone' );
}

sub test_gmt_datetime_from_timestamp()
{
    my $timestamp;
    my $datetime;
    my $datetime_2;

    # Start of epoch
    $timestamp = 0;
    $datetime  = MediaWords::Util::DateTime::gmt_datetime_from_timestamp( $timestamp );
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
    $datetime  = MediaWords::Util::DateTime::gmt_datetime_from_timestamp( $timestamp );
    isa_ok( $datetime, 'DateTime' );
    is( DateTime->compare( $datetime, $datetime_2 ), 0 );

    # Some other timezone
    $timestamp = DateTime->new(
        year      => 2017,
        month     => 3,
        day       => 3,
        hour      => 17,
        minute    => 0,
        second    => 0,
        time_zone => 'America/New_York'
    )->epoch;

    $datetime_2 = DateTime->new(    # same date, different TZ
        year      => 2017,
        month     => 3,
        day       => 3,
        hour      => 22,
        minute    => 0,
        second    => 0,
        time_zone => 'GMT'
    );
    $datetime = MediaWords::Util::DateTime::gmt_datetime_from_timestamp( $timestamp );
    isa_ok( $datetime, 'DateTime' );
    is( DateTime->compare( $datetime, $datetime_2 ), 0 );
}

sub test_gmt_date_string_from_timestamp()
{
    is( MediaWords::Util::DateTime::gmt_date_string_from_timestamp( 0 ),         '1970-01-01T00:00:00' );
    is( MediaWords::Util::DateTime::gmt_date_string_from_timestamp( -13849765 ), '1969-07-24T16:50:35' );
    is( MediaWords::Util::DateTime::gmt_date_string_from_timestamp( 637146000 ), '1990-03-11T09:00:00' );
}

sub test_str2time_21st_century()
{
    is( MediaWords::Util::DateTime::str2time_21st_century( '1961-01-01' ), timelocal( 0, 0, 0, 1, 0, 1961 ), 'Year 1961' );
    is( MediaWords::Util::DateTime::str2time_21st_century( '2061-01-01' ), timelocal( 0, 0, 0, 1, 0, 2061 ), 'Year 2061' );

    is(
        MediaWords::Util::DateTime::str2time_21st_century( '2016-08-23T23:32:11-04:00' ),
        DateTime->new(
            year      => 2016,
            month     => 8,
            day       => 23,
            hour      => 23,
            minute    => 32,
            second    => 11,
            time_zone => 'America/New_York'
          )->epoch(),
        'Univision test date'
    );

    my $str_dates_in_2061 = qq!2061-01-24
        2061-01-24T09:08:17.1823213
        2061-01-24T09:08:17
        Fri Dec 17 00:00:00 2061 GMT
        Tue Jan 16 23:59:59 2061 GMT
        2061-02-02 00:00:00 GMT
        2061-02-02 00:00:00 GMT
        16 Jun 61 07:29:35 CST 
        2061-02-26-10:37:21.141 GMT
        Wed, 16 Jun 61 07:29:35 CST 
        Wed, 16 Nov 61 07:29:35 CST 
        Mon, 21 Nov 61 07:42:23 CST 
        Mon, 21 Nov 61 04:28:18 CST 
        Tue, 15 Nov 61 09:15:10 GMT 
        Wed, 16 Nov 61 09:39:49 GMT 
        Wed, 16 Nov 61 09:23:17 GMT 
        Wed, 16 Nov 61 12:39:49 GMT 
        Wed, 16 Nov 61 14:03:06 GMT 
        Wed, 16 Nov 61 05:30:51 CST 
        Thu, 17 Nov 61 03:19:30 CST 
        Mon, 21 Nov 61 14:05:32 GMT 
        Mon, 14 Nov 61 15:08:49 CST 
        Wed, 16 Nov 61 14:48:06 GMT 
        Thu, 17 Nov 61 14:22:03 GMT 
        Wed, 16 Nov 61 14:36:00 GMT 
        Wed, 16 Nov 61 09:23:17 GMT 
        Wed, 16 Nov 61 10:01:43 GMT 
        Wed, 16 Nov 61 15:03:35 GMT 
        Mon, 21 Nov 61 13:55:19 GMT 
        Wed, 16 Nov 61 08:46:11 CST 
        21/dec/61 17:05
        dec/21/61 17:05
        Dec/21/2061 17:05:00
        dec-21-2061 17:05
        Dec-21-61 17:05:00
        dec 21 2061 17:05
        dec 21 61 17:05
        dec 21 61 17:05 GMT
        dec 21 61 17:05 BST
        dec 21 61 00:05 -1700
        dec 21 61 17:05 -1700
        Wed, 9 Nov 2061 09:50:32 -0500 (EST) 
        Thu, 13 Oct 61 10:13:13 -0700
        Sat, 19 Nov 2061 16:59:14 +0100 
        Thu, 3 Nov 61 14:10:47 EST 
        Thu, 3 Nov 61 21:51:09 EST 
        Fri, 4 Nov 61 9:24:52 EST 
        Wed, 9 Nov 61 09:38:54 EST 
        Mon, 14 Nov 61 13:20:12 EST 
        Wed, 16 Nov 61 17:09:13 EST 
        Tue, 15 Nov 61 12:27:01 PST 
        Fri, 18 Nov 2061 07:34:05 -0600 
        Mon, 21 Nov 61 14:34:28 -0500 
        Fri, 18 Nov 2061 12:05:47 -0800 (PST) 
        Fri, 18 Nov 2061 12:36:26 -0800 (PST) 
        Wed, 16 Nov 2061 15:58:58 GMT 
        2061 10:02:18 "GMT"
        Sun, 06 Nov 61 14:27:40 -0500 
        Mon, 07 Nov 61 08:20:13 -0500 
        Mon, 07 Nov 61 16:48:42 -0500 
        Wed, 09 Nov 61 15:46:16 -0500 
        Fri, 4 Nov 61 16:17:40 "PST 
        Wed, 16 Nov 61 12:43:37 "PST 
        Sun, 6 Nov 2061 02:38:17 -0800 
        Tue, 1 Nov 2061 13:53:49 -0500
        Tue, 15 Nov 61 08:31:59 +0100
        Sun, 6 Nov 2061 11:09:12 -0500 (IST)
        Fri, 4 Nov 61 12:52:10 EST
        Mon, 31 Oct 2061 14:17:39 -0500 (EST)
        Mon, 14 Nov 61 11:25:00 CST
        Mon, 14 Nov 61 13:26:29 CST
        Fri, 18 Nov 61 8:42:47 CST
        Thu, 17 Nov 61 14:32:01 +0900
        Wed, 2 Nov 61 18:16:31 +0100
        Fri, 18 Nov 61 10:46:26 +0100
        Tue, 8 Nov 2061 22:39:28 +0200
        Wed, 16 Nov 2061 10:01:08 -0500 (EST)
        Wed, 2 Nov 2061 16:59:42 -0800
        Wed, 9 Nov 61 10:00:23 PST
        Fri, 18 Nov 61 17:01:43 PST
        Mon, 14 Nov 2061 14:47:46 -0500
        Mon, 21 Nov 2061 04:56:04 -0500 (EST)
        Mon, 21 Nov 2061 11:50:12 -0800
        Sat, 5 Nov 2061 14:04:16 -0600 (CST)
        Sat, 05 Nov 61 13:10:13 MST
        Wed, 02 Nov 61 10:47:48 -0800
        Wed, 02 Nov 61 13:19:15 -0800
        Thu, 03 Nov 61 15:27:07 -0800
        Fri, 04 Nov 61 09:12:12 -0800
        Wed, 9 Nov 2061 10:13:03 +0000 (GMT) 
        Wed, 9 Nov 2061 15:28:37 +0000 (GMT) 
        Wed, 2 Nov 2061 17:37:41 +0100 (MET) 
        05 Nov 61 14:22:19 PST 
        16 Nov 61 22:28:20 PST 
        Tue, 1 Nov 2061 19:51:15 -0800 
        Wed, 2 Nov 61 12:21:23 GMT 
        Fri, 18 Nov 61 18:07:03 GMT 
        Wed, 16 Nov 2061 11:26:27 -0500 
        Sun, 6 Nov 2061 13:48:49 -0500 
        Tue, 8 Nov 2061 13:19:37 -0800 
        Fri, 18 Nov 2061 11:01:12 -0800 
        Mon, 21 Nov 2061 00:47:58 -0500 
        Mon, 7 Nov 2061 14:22:48 -0800 (PST) 
        Wed, 16 Nov 2061 15:56:45 -0800 (PST) 
        Thu, 3 Nov 2061 13:17:47 +0000 
        Wed, 9 Nov 2061 17:32:50 -0500 (EST)
        Wed, 9 Nov 61 16:31:52 PST
        Wed, 09 Nov 61 10:41:10 -0800
        Wed, 9 Nov 61 08:42:22 MST
        Mon, 14 Nov 2061 08:32:13 -0800
        Mon, 14 Nov 2061 11:34:32 -0500 (EST)
        Mon, 14 Nov 61 16:48:09 GMT
        Tue, 15 Nov 2061 10:27:33 +0000
        Wed, 02 Nov 61 13:56:54 MST
        Thu, 03 Nov 61 15:24:45 MST
        Thu, 3 Nov 2061 15:13:53 -0700 (MST)
        Fri, 04 Nov 61 08:15:13 MST
        Thu, 3 Nov 61 18:15:47 EST
        Tue, 08 Nov 61 07:02:33 MST
        Thu, 3 Nov 61 18:15:47 EST
        Tue, 15 Nov 61 07:26:05 MST
        Wed, 2 Nov 2061 00:00:55 -0600 (CST)
        Sun, 6 Nov 2061 01:19:13 -0600 (CST)
        Mon, 7 Nov 2061 23:16:57 -0600 (CST)
        Tue, 08 Nov 2061 13:21:21 -0600
        Mon, 07 Nov 61 13:47:37 PST
        Tue, 08 Nov 61 11:23:19 PST
        Tue, 01 Nov 2061 11:28:25 -0800
        Tue, 15 Nov 2061 13:11:47 -0800
        Tue, 15 Nov 2061 13:18:38 -0800
        Tue, 15 Nov 2061 0:18:38 -0800
        20610722T100000Z
        2061-07-22 10:00:00Z
        2061-07-22 10:00:00 Z
        2061-07-22 10:00 Z
        2061-07-22 10:00Z
        2061-07-22 10:00 +100
        2061-07-22 10:00 +0100
        61-02-01!;
    my @dates_in_2061 = split( /\n/, $str_dates_in_2061 );

    my $start_of_year = timelocal( 0,  0,  0,  1,  0,  2061 );
    my $end_of_year   = timelocal( 59, 59, 23, 31, 11, 2061 );

    foreach my $date_in_2061 ( @dates_in_2061 )
    {
        unless ( $date_in_2061 )
        {
            next;
        }
        $date_in_2061 =~ s/^\s+|\s+$//g;

        DEBUG "Testing date '$date_in_2061'...";

        my $timestamp = MediaWords::Util::DateTime::str2time_21st_century( $date_in_2061 );
        ok( $timestamp, "Date '$date_in_2061' is defined" );
        ok( ( $start_of_year <= $timestamp and $end_of_year >= $timestamp ), "Date '$date_in_2061' is within range" );
    }
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_local_timezone();
    test_gmt_datetime_from_timestamp();
    test_gmt_date_string_from_timestamp();
    test_str2time_21st_century();
}

main();
