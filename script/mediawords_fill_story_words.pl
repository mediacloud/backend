#!/usr/bin/env perl

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

use Perl6::Say;

use MediaWords::DB;
use MediaWords::CommonLibs;

use MediaWords::StoryVectors;

sub main
{

    my $db = MediaWords::DB::connect_to_db;

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    $db->dbh->{ AutoCommit } = 0;

    if ( $ARGV[ 0 ] eq '-d' )
    {
        say STDERR "dropping and refilling ssw_queue table ...";

	$db->query("TRUNCATE story_sentence_counts");
	$db->query("TRUNCATE story_sentence_words,story_sentences");

        $db->query( "drop table if exists ssw_queue" );
        $db->query( "create table ssw_queue as select stories_id, publish_date, media_id from stories order by stories_id" );
        $db->query( "create index ssw_queue_story on ssw_queue (stories_id)" );
        $db->commit;
    }

    say STDERR "running fill_story_sentence_words ...";

    MediaWords::StoryVectors::fill_story_sentence_words( $db );

    say STDERR "running update_aggregate_words ...";
    MediaWords::StoryVectors::update_aggregate_words( $db, '2008-01-01' );
}

main();
