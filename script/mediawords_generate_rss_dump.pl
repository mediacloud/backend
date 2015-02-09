#!/usr/bin/env perl

# query all story urls with a collect_date in the last N calendar days and
# generate an rss feed with just the url for each story, sorted by collect_date

# usage: $0 < num_days >

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Encode;
use XML::FeedPP;

use MediaWords::DB;

sub main
{
    my ( $num_days ) = @ARGV;

    die( "usage: $0 < num_days >" ) unless ( $num_days );

    my $db = MediaWords::DB::connect_to_db;

    my @urls = $db->query( <<SQL )->flat;
select url from stories where collect_date >  date_trunc( 'day', now() - '$num_days days'::interval ) order by collect_date desc
SQL

    my $feed = XML::FeedPP::RSS->new();
    $feed->title( "Media Cloud URL Dump" );
    $feed->link( "http://mediacloud.org/" );
    $feed->pubDate( time );

    for my $url ( @urls )
    {
        $feed->add_item( $url );
    }

    say STDERR "exporting " . scalar( @urls ) . " urls";

    print encode( 'utf8', $feed->to_string( indent => 4 ) );
}

main();
