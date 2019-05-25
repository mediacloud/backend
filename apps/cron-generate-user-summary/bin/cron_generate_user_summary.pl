#!/usr/bin/env perl

# print a summary of new users and user activity with configurable intervals

use strict;
use warnings;

use Getopt::Long;

use MediaWords::DB;

sub main
{
    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    my ( $new_user_interval, $activity_interval );

    Getopt::Long::GetOptions(
        "new=i"      => \$new_user_interval,
        "activity=i" => \$activity_interval
    ) || return;

    $new_user_interval ||= 1;
    $activity_interval ||= 7;

    my $db = MediaWords::DB::connect_to_db();

    print "Daily User Summary\n\n";

    {
        my $new_users = $db->query(
            <<SQL
            SELECT *
            FROM auth_users
            WHERE date_trunc( 'day', created_date ) >= date_trunc( 'day', NOW() - interval '$new_user_interval days')
            ORDER BY created_date
SQL
        )->hashes;

        print "New Users ($new_user_interval days):\n\n";
        map { print "* $_->{ full_name } <$_->{ email }>\n$_->{ notes }\n\n" } @{ $new_users };
    }

    print "\n";

    {
        my $counts = $db->query(
            <<SQL
            SELECT
                SUM(requests_count) AS requests_count,
                SUM(requested_items_count) AS requested_items_count,
                email,
                MAX(day) AS latest_day
            FROM auth_user_request_daily_counts
                WHERE day > date_trunc('week', NOW() - interval '$new_user_interval days')
            GROUP BY email
            ORDER BY SUM(requests_count) DESC
SQL
        )->hashes;

        print "Request Counts ($activity_interval days):\n\n* email requests / items / latest_day\n";

        map { print "* $_->{ email } $_->{ requests_count } / $_->{ requested_items_count } / $_->{ latest_day }\n" }
          @{ $counts };
    }
}

main();
