#!/usr/bin/perl

# delete any nyt topics tags that no longer exist in the nyt_topics list

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Tagger::NYTTopics;

sub main
{

    my $db = MediaWords::DB::authenticate();

    my $topics = MediaWords::Tagger::NYTTopics::get_topics_hash();

    my $tags_rs = $db->resultset( 'Tags' )->search( { 'tag_sets_id.name' => 'NYTTopics' }, { join => 'tag_sets_id' } );

    while ( my $tag = $tags_rs->next )
    {
        if ( !$topics->{ $tag->tag } )
        {
            print "delete " . $tag->tag . " ...\n";
            $tag->delete();
        }
    }
}

main();
