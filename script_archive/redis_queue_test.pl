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


my $stories = $db->query(
"SELECT * from authors_stories_map natural join authors natural join stories natural join ( select media_id, url as media_url, name as media_name, moderated, feeds_added, extract_author from media ) as m " . 
    " where date_trunc('day', publish_date) =  ?  order by authors_stories_map_id asc  limit 10" , 
#" SELECT * from authors_stories_map natural join authors natural join stories natural join media where date_trunc('day', publish_date) =  ?  order by authors_stories_map asc ",
    $date
);


if ( 1 )
{

    $r->flushdb();

    while ( my $story = $stories->hash )
    {

        #say $stories;
        #say $story;

        #3exit;
        #say Dumper( $story );

        say "Setting authors_stories_map_id: " . $story->{ authors_stories_map_id };
        my @story_list = %$story;

        #say "As " . Dumper( \@story_list);
        $r->hmset( $story->{ authors_stories_map_id }, @story_list );

	# foreach my $key ( keys % $story )
	# {
	#     say " Setting  " .  $story->{ authors_stories_map_id } . ", $key, $story->{ $key } ";

	#     $r->hset( $story->{ authors_stories_map_id }, $key, $story->{ $key } );

	#     last;
	# }
    }

    say "Set all stories ";

#    exit;
}

my $stories = $db->query(
"SELECT * from authors_stories_map natural join authors natural join stories natural join ( select media_id, url as media_url, name as media_name, moderated, feeds_added, extract_author from media ) as m " . 
    " where date_trunc('day', publish_date) =  ?  order by authors_stories_map_id asc  limit 10" , 
#" SELECT * from authors_stories_map natural join authors natural join stories natural join media where date_trunc('day', publish_date) =  ?  order by authors_stories_map asc ",
    $date
);

while ( my $story = $stories->hash )
{

    my $got = $r->hgetall( $story->{  authors_stories_map_id } );

    say Dumper( $got );

}

