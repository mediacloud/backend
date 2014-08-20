#!/usr/bin/env perl

# number of downloads to fetch at a time
use constant PROCESS_SIZE => 100;

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
use MediaWords::Util::Process;

use Text::Ngrams;
use Data::Dumper;

# fork of $num_processes
sub main
{
    my ( $num_processes ) = @ARGV;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    $num_processes ||= 1;

    # turn off buffering so processes don't write over each other as much
    $| = 1;

    my $db = MediaWords::DB::connect_to_db;

    $db->query( " DROP TABLE IF EXISTS ngram_test_story_sentence_words " );
    $db->query( " CREATE TABLE ngram_test_story_sentence_words (like story_sentence_words   " .
          " INCLUDING  DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES );" );

    $db->query( " DROP TABLE IF EXISTS ngram_test_story_sentences " );
    $db->query(
" CREATE TABLE ngram_test_story_sentences (like story_sentences INCLUDING  DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES );"
    );

    $db->query( "DROP TABLE IF EXISTS ngram_test_ngrams " );

    my $ngram_test_table_create = <<'SQL';
CREATE TABLE ngram_test_ngrams ( 
ngram_test_ngrams_id serial primary key,
stories_id int references stories on DELETE CASCADE,
ngram_length int NOT NULL,
ngram varchar(1024) NOT NULL,
count int NOT NULL
 );
SQL

    $db->query( $ngram_test_table_create );

    $db->query( "CREATE INDEX ngram_test_ngrams_stories_id on  ngram_test_ngrams(stories_id) " );
    $db->query( "CREATE INDEX ngram_test_ngrams_ngram on  ngram_test_ngrams(ngram) " );

    my $target_story_count = 1000;

    my $stories_ids =
      $db->query( 'SELECT stories.stories_id from stories order by RANDOM() limit ?', $target_story_count )->flat();

    #say Dumper($stories_ids);

    my $stories_processed = 0;

    foreach my $stories_id ( @$stories_ids )
    {
        if ( $stories_processed % 50 == 0 )
        {
            say "$stories_processed stories have been processed out of $target_story_count";
        }

        $db->query(
            "INSERT INTO ngram_test_story_sentences                                  " .
              " (select * from story_sentences where stories_id = ? ) ",
            $stories_id
        );

        $db->query(
            "INSERT INTO ngram_test_story_sentence_words                                  " .
              " (select * from story_sentence_words where stories_id = ? ) ",
            $stories_id
        );

        my $sentences = $db->query( " SELECT SENTENCE from story_sentences where stories_id = ? ", $stories_id )->flat();

        #say Dumper( $sentences );

        my $window_size = 4;
        my $ng = Text::Ngrams->new( windowsize => $window_size, type => 'word' );

        $ng->process_text( @{ $sentences } );

        foreach my $ngram_length ( 1 .. $window_size )
        {
            my @ngrams = $ng->get_ngrams( n => $ngram_length );

            while ( scalar( @ngrams ) )
            {
                my $count;
                my $ngram = shift @ngrams;
                $count = shift @ngrams;

                # say Dumper [ $ngram, $count ];

                $db->query( " INSERT INTO ngram_test_ngrams (stories_id, ngram_length, ngram, count) VALUES (?, ?, ?, ?) ",
                    $stories_id, $ngram_length, $ngram, $count );
            }
        }

        $stories_processed++;

        #exit;
    }
}

main();
