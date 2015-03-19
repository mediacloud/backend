#!/usr/bin/env perl

# print a summary of the various crawler queues

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

    my $pending_downloads = $db->query( <<SQL )->hashes;
select count(*) c, date_trunc( 'hour', download_time) download_time
    from downloads
    where state = 'pending'
    group by date_trunc( 'hour', download_time)
    order by date_trunc( 'hour', download_time);
SQL

}

main();
