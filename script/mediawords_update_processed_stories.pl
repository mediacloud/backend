#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::MC_Fork;

sub update_processed_stories
{
    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    my $last_story_sentences_id_processed =
      ( $db->query( " SELECT value from database_variables where name = 'LAST_STORY_SENTENCES_ID_PROCESSED' " )->flat() )
      [ 0 ];

    die unless defined( $last_story_sentences_id_processed );

    my $stop_story_sentences_id = ( $db->query( " SELECT max(story_sentences_id) from story_sentences" )->flat() )[ 0 ];

    if ( $last_story_sentences_id_processed == $stop_story_sentences_id )
    {
        say STDERR "processed_stories is up to date. Stop story_sentences_id = $stop_story_sentences_id";
        return;
    }

    if ( ( $stop_story_sentences_id - $last_story_sentences_id_processed ) > 10_000 )
    {
	$stop_story_sentences_id = $last_story_sentences_id_processed + 10_000;
    }

    say STDERR "Updating processed stories from $last_story_sentences_id_processed to $stop_story_sentences_id";

    $db->query(
" INSERT INTO processed_stories ( stories_id ) select distinct( stories_id ) from story_sentences where story_sentences_id >? and story_sentences_id <= ? ",
        $last_story_sentences_id_processed, $stop_story_sentences_id
    );

    $db->query( "UPDATE database_variables SET value = ? where name =  'LAST_STORY_SENTENCES_ID_PROCESSED' ",
        $stop_story_sentences_id );

    $db->commit;

}

sub main
{
    if ( ( scalar( @ARGV ) >= 1 ) && $ARGV[ 0 ] eq '-d' )
    {
        while ( 1 )
        {
            update_processed_stories();
            say STDERR "Sleeping...";
            sleep( 1 );
        }
    }
    else
    {
        update_processed_stories();

    }
}

main();
