#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::MC_Fork;

# extract, story, and tag downloaded text a slice of downloads.
# downloads are extracted by a total of num_total_jobs processings
# a total of num_total_processes, with a unique 1-indexed job_number
# for each job
sub extract_text
{
    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    my $last_story_sentences_id_processed = ( $db->query(" SELECT value from database_variables where name = 'LAST_STORY_SENTENCES_ID_PROCESSED' ")->flat() ) [0];

    die unless defined( $last_story_sentences_id_processed );

    my $stop_story_sentences_id = ( $db->query( " SELECT max(story_sentences_id) from story_sentences" )->flat())[0];

    $db->query(" INSERT INTO processed_stories ( stories_id ) select distinct( stories_id ) from story_sentences where story_sentences_id >? and story_sentences_id <= ? order by stories_id" , $last_story_sentences_id_processed, $stop_story_sentences_id );

    $db->query( "UPDATE database_variables SET value = ? where name =  'LAST_STORY_SENTENCES_ID_PROCESSED' ",
		$stop_story_sentences_id );

    $db->commit;
    
}

# fork of $num_processes
sub main
{
    extract_text();
}

# use Test::LeakTrace;
# leaktrace { main(); };

main();
