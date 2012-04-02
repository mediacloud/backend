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

GetOptions(
    'server=s'      => \$server,
    'port=s' => \$port,
    ) or die;

die  unless $server && $port;

say "starting";

my $r = Redis->new( server => "$server:$port", debug => 0 );

#my $hash = { key1 => 'val1', key2 => 'val2' };

#$r->hmset( 'foo', ( %$hash ) );

my $db = MediaWords::DB::connect_to_db();

#my $stories = $db->query(" SELECT * from stories ORDER by stories_id asc limit 10 " )->hashes;

my $stories = $db->query(
" SELECT * from authors_stories_map natural join authors natural join stories where date_trunc('day', publish_date) =  ? order by authors_stories_map asc limit 10;",
    '2012-04-02'
);

#say Dumper( $stories );
#exit;

if ( 1 )
{
    while ( my $story = $stories->hash )
    {

        #say $stories;
        #say $story;

        #3exit;
        #say Dumper( $story );

        say "Setting story: " . $story->{ stories_id };
        my @story_list = %$story;

        #say "As  @story_list";
        $r->hmset( $story->{ stories_id }, @story_list );
    }

    say "Set all stories ";

    exit;
}

#$r->flushdb();

while ( my $story = $stories->hash )
{
    my $got = $r->hgetall( $story->{ stories_id } );

    say Dumper( $got );

}

# my $r_q = Redis::Queue->new( redis=> $r, queue => 'mc_queue' );

#

#$r_q->sendMessage( %$hash );

#$r_q->sendMessage( 10, 10, 10 );

#my ($id, $val) = $r_q->receiveMessage();

#use Data::Dumper;

#say Dumper( [ $id, $val ] );
