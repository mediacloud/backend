#!/usr/bin/perl

# check for duplicate sentences among existing stories and remove story_sentences and story_sentence_words rows for
# duplicates.  the StoryVectors stuff does this automagically now as each story is vectored.  This is only needed to
# retroactively fix the data we generated before we had the dedup stuff in StoryVectors.

# this script can be stopped and restarted repeatedly, and it will do the right thing, however it assumes that it is
# starting with a blank story_sentence_counts table and will try to dedup all sentences in the db.  you should not
# have deduping running via StoryVectors / mediawords_extract_text.pl until after this script finishes deduping all
# existing sentences

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;

# return the number of sentences of this sentence within the same media source and calendar week.
# also adds the sentence to the story_sentence_counts table and/or increments the count in that table
# for the sentence.  Note that this is not a perfect count -- we don't try to lock this b/c it's not
# worth the performance hit, so multiple initial entries for a given sentence might be created (even
# though the order by on the select will minimize this effect).
#
# this is copy and pasted from MediaWords::StoryVectors because I need to run it in production before plugging
# the new version of StoryVectors in production, which includes other updates as well.
sub count_duplicate_sentences
{
    my ( $db, $sentence, $sentence_number, $story ) = @_;

    my $dup_sentence = $db->query(
        "select * from story_sentence_counts " .
          "  where sentence_md5 = md5( ? ) and media_id = ? and publish_week = date_trunc( 'week', ?::date )" .
          "  order by story_sentence_counts_id limit 1",
        $sentence,
        $story->{ media_id },
        $story->{ publish_date }
    )->hash;

    if ( $dup_sentence )
    {
        $db->query(
            "update story_sentence_counts set sentence_count = sentence_count + 1 " . "  where story_sentence_counts_id = ?",
            $dup_sentence->{ story_sentence_counts_id }
        );
        return $dup_sentence->{ sentence_count };
    }
    else
    {
        $db->query(
            "insert into story_sentence_counts( sentence_md5, media_id, publish_week, " .
              "    first_stories_id, first_sentence_number, sentence_count ) " .
              "  values ( md5( ? ), ?, date_trunc( 'week', ?::date ), ?, ?, 1 )",
            $sentence,
            $story->{ media_id },
            $story->{ publish_date },
            $story->{ stories_id },
            $sentence_number
        );
        return 0;
    }
}

sub main
{

    my ( $start_date ) = @ARGV;

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    my ( $last_stories_id ) =
      $db->query( "select first_stories_id from story_sentence_counts " . "  where story_sentence_counts_id = 0" )->flat;

    $last_stories_id ||= 0;

    my $stories_query;
    if ( $start_date )
    {
        $stories_query =
          "select * from stories where stories_id > ? " .
          "and publish_date > '$start_date'::date order by stories_id limit 100";
    }
    else
    {
        $stories_query = "select * from stories where stories_id > ? order by stories_id limit 100";
    }

    while ( my $stories = $db->query( $stories_query, $last_stories_id )->hashes )
    {
        my $deleted_sentence_count = 0;
        my $total_sentence_count   = 0;

        for my $story ( @{ $stories } )
        {
            my $sentences =
              $db->query( "select * from story_sentences where stories_id = ?", $story->{ stories_id } )->hashes;
            for my $sentence ( @{ $sentences } )
            {
                $total_sentence_count++;
                my $num_dups =
                  count_duplicate_sentences( $db, $sentence->{ sentence }, $sentence->{ sentence_number }, $story );

                if ( $num_dups > 0 )
                {
                    $db->query(
                        "delete from story_sentences where stories_id = ? and sentence_number = ?",
                        $sentence->{ stories_id },
                        $sentence->{ sentence_number }
                    );
                    $db->query(
                        "delete from story_sentence_words where stories_id = ? and sentence_number = ?",
                        $sentence->{ stories_id },
                        $sentence->{ sentence_number }
                    );

                    $deleted_sentence_count++;
                }
            }

            $last_stories_id = $story->{ stories_id };
        }

        print STDERR "stories_id: $last_stories_id ($deleted_sentence_count / $total_sentence_count sentences deleted)\n";
        $db->delete_by_id( 'story_sentence_counts', 0 );
        $db->create(
            'story_sentence_counts',
            {
                sentence_md5             => 'na',
                media_id                 => 0,
                publish_week             => '2010-01-01',
                sentence_count           => 0,
                first_sentence_number    => 0,
                first_stories_id         => $last_stories_id,
                story_sentence_counts_id => 0
            }
        );

        $db->commit;
    }

}

main();
