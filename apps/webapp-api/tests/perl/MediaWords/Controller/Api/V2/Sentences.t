use strict;
use warnings;
use utf8;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::DB;
use MediaWords::Test::API;
use MediaWords::Test::Rows;
use MediaWords::Test::Solr;
use MediaWords::Test::DB::Create;

use MediaWords::Util::ParseJSON;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

Readonly my $UTF8_PREFIX => '𝑇ℎ𝑖𝑠 𝑝𝑎𝑟𝑡 𝑜𝑓 𝑡ℎ𝑒 𝑠𝑒𝑛𝑡𝑒𝑛𝑐𝑒 𝑖𝑠 𝑈𝑇𝐹-8 ';

sub test_sentences_list($)
{
    my ( $db ) = @_;

    my $label = "sentences/list";

    my $stories     = $db->query( "select * from stories order by stories_id asc limit 10" )->hashes;
    my $stories_ids = [ map { $_->{ stories_id } } @{ $stories } ];
    my $expected_ss = $db->query( <<SQL,
        SELECT *
        FROM story_sentences
        WHERE stories_id IN (??)
SQL
        @{ $stories_ids }
    )->hashes;

    my $stories_ids_list = join( ' ', @{ $stories_ids } );
    my $got_ss = MediaWords::Test::API::test_get( '/api/v2/sentences/list', { 'q' => "stories_id:($stories_ids_list)" } );

    WARN( MediaWords::Util::ParseJSON::encode_json( $got_ss ) );

    my $fields = [ qw/stories_id media_id sentence language publish_date/ ];
    MediaWords::Test::Rows::rows_match( $label, $got_ss, $expected_ss, 'story_sentences_id', $fields );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    my $media = MediaWords::Test::DB::Create::create_test_story_stack_numerated(
        $db,
        $NUM_MEDIA,
        $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED
    );

    $media = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $db, $media );

    # Prepend some UTF-8 to every sentence to test out Unicode support
    $db->query(<<SQL,
        UPDATE story_sentences
        SET sentence = CONCAT(?, sentence)
SQL
        $UTF8_PREFIX . ''
    );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    test_sentences_list( $db );

    done_testing();
}

main();
