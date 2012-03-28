#!/usr/bin/perl

# add archives for all existing feeds

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::DBI::Feeds;

sub main
{

    my $db = MediaWords::DB::connect_to_db();

    $db->dbh->{ AutoCommit } = 0;

    my $feeds = $db->query( "select * from feeds order by feeds_id desc" )->hashes;

    for my $feed ( @{ $feeds } )
    {
        print "feed: $feed->{feeds_id}\n";
        MediaWords::DBI::Feeds::add_archive_feed_downloads( $db, $feed );
        $db->commit();
    }

}

main();
