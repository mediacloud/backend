#!/usr/bin/env perl

# print a summary of user activity yesterday

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $counts = $db->query( <<END )->hashes;
select 
        sum( requests_count ) requests_count, sum( requested_items_count ) requested_items_count, email, max( day ) latest_day                     
    from auth_user_request_daily_counts
    where day > date_trunc( 'week', now() - interval '7 day' )
    group by email
    order by sum( requests_count ) desc;
END

    my $new_users = $db->query( <<END )->hashes;
select * 
    from auth_users
    where date_trunc( 'day', created_date ) > date_trunc( 'day', now() - interval '1 day' )
    order by created_date
END

    print "Daily User Summary\n\nNew Users Yesterday:\n\n";

    map { print "* $_->{ full_name } <$_->{ email }>\n$_->{ notes }\n\n" } @{ $new_users };

    print "\nRequest Counts This Week:\n\n* email requests / items / latest_day\n";

    map { print "* $_->{ email } $_->{ requests_count } / $_->{ requested_items_count } / $_->{ latest_day }\n" }
      @{ $counts };
}

main();
