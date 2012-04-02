#!/usr/bin/env perl
use strict;
use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use 5.14.2;

use Redis;
use Getopt::Long;

use Data::Dumper;
use MediaWords::DB;


my $server;
my $port;
my $date;

GetOptions(
    'server=s'      => \$server,
    'port=s' => \$port,
    'date=s' => \$date
    ) or die;

die  unless $server && $port;

say "starting";

my $r = Redis->new( server => "$server:$port", debug => 0 );

my $db = MediaWords::DB::connect_to_db();

my $query_rows = $db->query(
"SELECT * from authors_stories_map natural join authors natural join stories natural join ( select media_id, url as media_url, name as media_name, moderated, feeds_added, extract_author from media ) as m " . 
    " where date_trunc('day', publish_date) =  ?  order by authors_stories_map_id asc  limit 10" , 
    $date
);

if ( 1 )
{

    $r->flushdb();

    while ( my $query_row = $query_rows->hash )
    {

        #say $$query_rows;
        #say $query_row;

        #exit;
        #say Dumper( $query_row );

        say "Setting authors_stories_map_id: " . $query_row->{ authors_stories_map_id };
        my @row_list = %$query_row;

        #say "As " . Dumper( \@row_list);
        $r->hmset( $query_row->{ authors_stories_map_id }, @row_list );

    }

    say "Set all stories ";

#    exit;
}

my $query_rows = $db->query(
"SELECT * from authors_stories_map natural join authors natural join stories natural join ( select media_id, url as media_url, name as media_name, moderated, feeds_added, extract_author from media ) as m " . 
    " where date_trunc('day', publish_date) =  ?  order by authors_stories_map_id asc  limit 10" , 
#" SELECT * from authors_stories_map natural join authors natural join stories natural join media where date_trunc('day', publish_date) =  ?  order by authors_stories_map asc ",
    $date
);

while ( my $query_row = $query_rows->hash )
{

    my $got = $r->hgetall( $query_row->{  authors_stories_map_id } );

    say Dumper( $got );

}

