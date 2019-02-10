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

use MediaWords::Util::ParseJSON;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

sub test_sentences_count($)
{
    my ( $db ) = @_;

    my $label = "sentences/count";

    my $stories = $db->query( "select * from stories order by stories_id asc limit 10" )->hashes;
    my $stories_ids = [ map { $_->{ stories_id } } @{ $stories } ];
    ok( scalar( @{ $stories_ids } ) );
    my $ss = $db->query( 'select * from story_sentences where stories_id in ( ?? )', @{ $stories_ids } )->hashes;

    my $stories_ids_list = join( ' ', @{ $stories_ids } );
    my $r = MediaWords::Test::API::test_get( '/api/v2/sentences/count', { q => "stories_id:($stories_ids_list)" } );

    # we import titles as sentences as well as the sentences themselves, so expect them in the count
    my $expected_count = scalar( @{ $ss } ) + 10;

    is( $r->{ count }, $expected_count, "$label count" );
}

sub test_sentences_list($)
{
    my ( $db ) = @_;

    my $label = "sentences/list";

    my $stories     = $db->query( "select * from stories order by stories_id asc limit 10" )->hashes;
    my $stories_ids = [ map { $_->{ stories_id } } @{ $stories } ];
    my $expected_ss = $db->query( <<SQL, @{ $stories_ids } )->hashes;
select * from story_sentences where stories_id in ( ?? )
SQL

    my $stories_ids_list = join( ' ', @{ $stories_ids } );
    my $got_ss = MediaWords::Test::API::test_get( '/api/v2/sentences/list', { q => "stories_id:($stories_ids_list)" } );

    WARN( MediaWords::Util::ParseJSON::encode_json( $got_ss ) );

    my $fields = [ qw/stories_id media_id sentence language publish_date/ ];
    MediaWords::Test::DB::rows_match( $label, $got_ss, $expected_ss, 'story_sentences_id', $fields );
}

sub test_sentences($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    $media = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    # test_sentences_count( $db );
    # test_sentences_field_count( $db );
    test_sentences_list( $db );
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_sentences,
        [ 'solr_standalone', 'job_broker:rabbitmq', 'rescrape_media' ] );

    done_testing();
}

main();
