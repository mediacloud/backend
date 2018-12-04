use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::Test::API;
use MediaWords::Test::DB;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;

use MediaWords::Languages::Language;
use MediaWords::Util::IdentifyLanguage;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

# test wc/list end point
sub test_wc_list($)
{
    my ( $db ) = @_;

    test_get( '/api/v2/wc/list', { q => 'the' } );

    my $label = "wc/list";

    my $story = $db->query( "select * from stories order by stories_id limit 1" )->hash;

    my $sentences = $db->query( <<SQL, $story->{ stories_id } )->flat;
select sentence from story_sentences where stories_id = ?
SQL

    my $expected_word_counts = {};
    for my $sentence ( @{ $sentences } )
    {
        my $sentence_language = MediaWords::Util::IdentifyLanguage::language_code_for_text( $sentence );
        unless ( $sentence_language )
        {
            TRACE "Unable to determine sentence language for sentence '$sentence', falling back to English";
            $sentence_language = 'en';
        }
        unless ( MediaWords::Languages::Language::language_is_enabled( $sentence_language ) )
        {
            TRACE "Language '$sentence_language' for sentence '$sentence' is not enabled, falling back to English";
            $sentence_language = 'en';
        }

        my $lang = MediaWords::Languages::Language::language_for_code( $sentence_language );

        my $words = $lang->split_sentence_to_words( $sentence );
        my $stems = $lang->stem_words( $words );
        map { $expected_word_counts->{ $_ }++ } @{ $stems };
    }

    my $got_word_counts = test_get(
        '/api/v2/wc/list',
        {
            q         => "stories_id:$story->{ stories_id }",
            num_words => 10000,

            # don't try to test stopwording
            include_stopwords => 1,
        }
    );

    is( scalar( @{ $got_word_counts } ), scalar( keys( %{ $expected_word_counts } ) ), "$label number of words" );

    for my $got_word_count ( @{ $got_word_counts } )
    {
        my $stem = $got_word_count->{ stem };
        ok( $expected_word_counts->{ $stem }, "$label word count for '$stem' is found but not expected" );
        is( $got_word_count->{ count }, $expected_word_counts->{ $stem }, "$label expected word count for '$stem'" );
    }
}

sub test_media($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    $media = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    test_wc_list( $db );
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_media,
        [ 'solr_standalone', 'job_broker:rabbitmq', 'rescrape_media' ] );

    done_testing();
}

main();
