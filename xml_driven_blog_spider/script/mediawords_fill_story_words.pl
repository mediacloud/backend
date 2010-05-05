#!/usr/bin/perl

# fill the *_words tables from scratch (or refill if they have already been filled)

# usage: mediawords_fill_story_words.pl [-d]
#
# the -d option makes the script drop and recreate the ssw_queue table before running fill_story_sentence_words()

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;
use MediaWords::DB;

sub main {
    
    my $db = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);
    
    if ( $ARGV[0] eq '-d' )
    {
        print "dropping and refilling ssw_queue table ...\n";
    
        $db->query( "drop table if exists ssw_queue" );
        $db->query( "create table ssw_queue as select stories_id, publish_date, media_id from stories" );
    }
    
    print "running fill_story_sentence_words ...\n";
    
    while ( 'more' eq $db->query( "select fill_story_sentence_words()" )->list )
    {
    }
    
    print "running update_aggregate_words\n";
    
    $db->query( "select update_aggregate_words()" );

}

main();
