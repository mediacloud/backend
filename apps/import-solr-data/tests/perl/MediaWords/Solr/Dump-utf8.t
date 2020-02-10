use strict;
use warnings;

use utf8;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::Test::DB::Create;
use MediaWords::Test::Solr;

sub test_import_utf8($)
{
    my ( $db ) = @_;

    my $test_medium = MediaWords::Test::DB::Create::create_test_medium( $db, 'test' );
    my $test_feed = MediaWords::Test::DB::Create::create_test_feed( $db, 'test', $test_medium );

    my $test_story = $db->create( 'stories', {
        'media_id' => $test_medium->{ 'media_id' },
        'url' => 'https://www.example.com/azuolas_berzas_ir_liepa.html',
        'guid' => 'https://www.example.com/azuolas_berzas_ir_liepa.html',
        'title' => 'ąžuolas',
        'description' => '',
        'publish_date' => '2020-02-05 14:06:00',
        'collect_date' => '2020-02-05 18:18:47.271006',
        'full_text_rss' => 'f',
        'language' => 'lt',
    } );

    $db->create( 'feeds_stories_map', {
        'feeds_id' => $test_feed->{ 'feeds_id' },
        'stories_id' => $test_story->{ 'stories_id' },
    });

    $test_story->{ 'content' } = 'beržas';

    $test_story = MediaWords::Test::DB::Create::add_content_to_test_story( $db, $test_story, $test_feed );

    MediaWords::Test::Solr::setup_test_index( $db );

    {
        my $num_solr_stories = MediaWords::Solr::get_num_found( $db, { 'q' => 'title:ąžuolas' } );
        ok( $num_solr_stories > 0, "UTF-8 stories were found by title" );
    }

    {
        my $num_solr_stories = MediaWords::Solr::get_num_found( $db, { 'q' => 'text:beržas' } );
        ok( $num_solr_stories > 0, "UTF-8 stories were found by text" );
    }
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_import_utf8( $db );

    done_testing();
}

main();
