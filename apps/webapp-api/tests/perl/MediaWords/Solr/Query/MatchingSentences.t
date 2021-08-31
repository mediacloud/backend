use strict;
use warnings;

use MediaWords::CommonLibs;

use Data::Dumper;
use Test::More;
use Test::Deep;

use MediaWords::DB;
use MediaWords::Solr::Query::MatchingSentences;
use MediaWords::Test::DB::Create;
use MediaWords::Test::Solr;
use MediaWords::Test::Rows;

sub test_query_matching_sentences($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::Solr::create_indexed_test_story_stack(
        $db,
        {
            medium_1 => { feed_1 => [ map { "story_$_" } ( 1 .. 15 ) ] },
            medium_2 => { feed_2 => [ map { "story_$_" } ( 16 .. 25 ) ] },
            medium_3 => { feed_3 => [ map { "story_$_" } ( 26 .. 50 ) ] },
        }
    );

    my $test_stories = $db->query( "select * from stories order by md5( stories_id::text )" )->hashes;

    {
        # query_matching_sentences
        my $story = pop( @{ $test_stories } );
        my $story_sentences = $db->query( <<SQL, $story->{ stories_id } )->hashes;
select * from story_sentences where stories_id = ?
SQL
        my ( $test_word ) = grep { length( $_ ) > 3 } split( ' ', $story_sentences->[ 0 ]->{ sentence } );

        $test_word = lc( $test_word );

        my $expected_sentences = [ grep { $_->{ sentence } =~ /\b$test_word\b/i } @{ $story_sentences } ];
        my $query              = "$test_word* and stories_id:$story->{ stories_id }";
        my $got_sentences      = MediaWords::Solr::Query::MatchingSentences::query_matching_sentences( $db, { q => $query } );

        my $fields = [ qw/stories_id sentence_number sentence media_id publish_date language/ ];
        MediaWords::Test::Rows::rows_match( "query_matching_sentences '$test_word'",
            $got_sentences, $expected_sentences, 'story_sentences_id', $fields );
    }

    {
        # query matching sentences with query with no text terms
        my $story = pop( @{ $test_stories } );
        my $story_sentences = $db->query( <<SQL, $story->{ stories_id } )->hashes;
select * from story_sentences where stories_id = ?
SQL
        my $query = "stories_id:$story->{ stories_id }";
        my $got_sentences = MediaWords::Solr::Query::MatchingSentences::query_matching_sentences( $db, { q => $query } );

        my $fields = [ qw/stories_id sentence_number sentence media_id publish_date language/ ];
        MediaWords::Test::Rows::rows_match( 'query_matching_sentences empty regex', $got_sentences, $story_sentences, 'story_sentences_id',
            $fields );
    }
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_query_matching_sentences( $db );

    done_testing();
}

main();
