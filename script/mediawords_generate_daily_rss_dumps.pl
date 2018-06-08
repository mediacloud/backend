#!/usr/bin/env perl

# generate daily rss dumps for the past 30 days.  remove any existing rss dumps older than 30 days.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Encode;
use File::Slurp;
use XML::FeedPP;

use MediaWords::Util::SQL;
use MediaWords::DB;

sub generate_daily_dump($$$)
{
    my ( $db, $dir, $day ) = @_;

    die( "day '$day' should be in YYYY-MM-DD format" ) unless ( $day =~ /^\d\d\d\d-\d\d-\d\d$/ );

    my $file = "$dir/mc-$day.rss";

    if ( -f $file )
    {
        INFO( "$file already exists.  skipping ..." );
        return;
    }

    INFO( "querying stories for $day ..." );

    my $stories = $db->query( <<SQL, $day )->hashes;
select url, guid
    from stories
        where
            collect_date >= \$1::date and
            collect_date < \$1::date + '1 day'::interval
        order by collect_date desc
SQL

    INFO "exporting " . scalar( @{ $stories } ) . " urls ...";

    my $feed = XML::FeedPP::RSS->new();
    $feed->title( "Media Cloud URL Snapshot for $day" );
    $feed->link( "http://mediacloud.org/" );
    $feed->pubDate( time );

    map { $feed->add_item( link => $_->{ url }, guid => $_->{ guid } ) } @{ $stories };

    File::Slurp::write_file( "$dir/mc-$day.rss", encode_utf8( $feed->to_string( indent => 4 ) ) );
}

sub main
{
    my ( $dir ) = @ARGV;

    die( "usage: $0 < dir >" ) unless ( $dir );

    die( "dir '$dir' does not exist" ) unless ( -d $dir );

    my $db = MediaWords::DB::connect_to_db();

    my $date = MediaWords::Util::SQL::increment_day( MediaWords::Util::SQL::sql_now(), -1 );
    for my $i ( 1 .. 30 )
    {
        $date = MediaWords::Util::SQL::increment_day( $date, -1 );
        DEBUG( $date );
        my $day = substr( $date, 0, 10 );
        generate_daily_dump( $db, $dir, $day );
    }

    my $files = [ grep( /rss$/, File::Slurp::read_dir( $dir ) ) ];
    for my $file ( @{ $files } )
    {
        my $path = "$dir/$file";
        if ( ( stat( $path ) )[ 9 ] < ( time() - ( 30 * 86400 ) ) )
        {
            INFO( "deleting old file $path ..." );
            unlink( $path );
        }
    }
}

main();
