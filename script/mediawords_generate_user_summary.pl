#!/usr/bin/env perl

# print a summary of user activity last week

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::DB;

sub main
{
    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    my ( $new_user_interval, $activity_interval );

    Getopt::Long::GetOptions(
        "new=i"         => \$new_user_interval,
        "activity=i"    => \$activity_interval
    ) || return;

    $new_user_interval ||= 1;
    $activity_interval ||= 7;

    my $db = MediaWords::DB::connect_to_db;

    my $counts = $db->query( <<END )->hashes;
select
        sum( requests_count ) requests_count, sum( requested_items_count ) requested_items_count, email, max( day ) latest_day
    from auth_user_request_daily_counts
    where day > date_trunc( 'week', now() - interval '$new_user_interval days' )
    group by email
    order by sum( requests_count ) desc;
END

    my $new_users = $db->query( <<END )->hashes;
select *
    from auth_users
    where date_trunc( 'day', created_date ) >= date_trunc( 'day', now() - interval '$new_user_interval days' )
    order by created_date
END

    print "Daily User Summary\n\nNew Users ($new_user_interval days):\n\n";

    map { print "* $_->{ full_name } <$_->{ email }>\n$_->{ notes }\n\n" } @{ $new_users };

    print "\nRequest Counts ($activity_interval days):\n\n* email requests / items / latest_day\n";

    map { print "* $_->{ email } $_->{ requests_count } / $_->{ requested_items_count } / $_->{ latest_day }\n" }
      @{ $counts };
}

main();
