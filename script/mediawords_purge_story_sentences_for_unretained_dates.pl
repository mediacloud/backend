#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Pg::Schema;
use Perl6::Say;
use Term::Prompt;

sub main
{
    my $warning_message =
"Warning this script will delete data from the story_sentences, story_sentences_words, and story_sentence_counts tables. Are you sure you wish to continue?";

    my $continue_and_reset_db = &prompt( "y", $warning_message, "", "n" );

    exit if !$continue_and_reset_db;

    my $db = MediaWords::DB::connect_to_db;

    MediaWords::StoryVectors::purge_story_words_data_for_unretained_dates( $db );
    MediaWords::StoryVectors::purge_story_sentences_data_for_unretained_dates( $db );
    MediaWords::StoryVectors::purge_story_sentence_counts_data_for_unretained_dates( $db );
}

main();
