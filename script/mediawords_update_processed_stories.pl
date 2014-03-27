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

    my $last_story_sentences_id_processed = (
        $db->query(
            <<EOF
        SELECT value
        FROM database_variables
        WHERE name = 'LAST_STORY_SENTENCES_ID_PROCESSED'
EOF
        )->flat()
    )[ 0 ];

    unless ( defined( $last_story_sentences_id_processed ) )
    {
        die "'LAST_STORY_SENTENCES_ID_PROCESSED' variable is undefined.\n";
    }

    my $stop_story_sentences_id = (
        $db->query(
            <<EOF
        SELECT MAX(story_sentences_id)
        FROM story_sentences
EOF
        )->flat()
    )[ 0 ];

    if ( $last_story_sentences_id_processed == $stop_story_sentences_id )
    {
        say STDERR "'processed_stories' is up to date. Stop story_sentences_id = $stop_story_sentences_id";
        return;
    }

    if ( ( $stop_story_sentences_id - $last_story_sentences_id_processed ) > 10_000 )
    {
        $stop_story_sentences_id = $last_story_sentences_id_processed + 10_000;
    }

    say STDERR "Updating processed stories from $last_story_sentences_id_processed to $stop_story_sentences_id...";

    $db->query(
        <<EOF,
        INSERT INTO processed_stories ( stories_id )
            SELECT DISTINCT stories_id
            FROM story_sentences
            WHERE story_sentences_id > ?
              AND story_sentences_id <= ?
EOF
        $last_story_sentences_id_processed, $stop_story_sentences_id
    );

    $db->query(
        <<EOF,
        UPDATE database_variables
        SET value = ?
        WHERE name = 'LAST_STORY_SENTENCES_ID_PROCESSED'
EOF
        $stop_story_sentences_id
    );

    $db->commit;

    say STDERR "Updated processed stories from $last_story_sentences_id_processed to $stop_story_sentences_id.";
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
