use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Solr::Query;
use MediaWords::Test::DB::Create;

use Time::Piece;

# test that MediaWords::Solr::Query::get_full_solr_query_for_topic() returns the expected query
sub test_get_full_solr_query_for_topic($)
{
    my ( $db ) = @_;

    WARN( "BEGIN test_full_solr_query" );

    MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, 10, 2, 2 );

    # just need some randomly named tags, so copying media names works as well as anything
    $db->query( "insert into tag_sets( name ) values ('foo' )" );

    $db->query( "insert into tags ( tag, tag_sets_id ) select media.name, tag_sets_id from media, tag_sets" );

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'full solr query' );
    my $topics_id = $topic->{ topics_id };

    $db->query( "insert into topics_media_map ( topics_id, media_id ) select ?, media_id from media limit 5",   $topics_id );
    $db->query( "insert into topics_media_tags_map ( topics_id, tags_id ) select ?, tags_id from tags limit 5", $topics_id );

    my $got_full_solr_query = MediaWords::Solr::Query::get_full_solr_query_for_topic( $db, $topic );

    my @q_matches =
      $got_full_solr_query->{ q } =~ /\( (.*) \) and \( media_id:\( ([\d\s]+) \) or tags_id_media:\( ([\d\s]+) \) \)/;
    ok( @q_matches, "full solr query: q matches expected pattern: $got_full_solr_query->{ q }" );
    my ( $query, $media_ids_list, $tags_ids_list ) = @q_matches;

    my @fq_matches = $got_full_solr_query->{ fq } =~
      /publish_day\:\[(\d\d\d\d\-\d\d\-\d\d)T00:00:00Z TO (\d\d\d\d\-\d\d\-\d\d)T23:59:59Z\]/;
    ok( @fq_matches, "full solr query: fq matches expected pattern: $got_full_solr_query->{ fq }" );
    my ( $start_date, $end_date ) = @fq_matches;

    is( $topic->{ solr_seed_query }, $query, "full solr query: solr_seed_query" );

    is( $topic->{ start_date }, $start_date, "full solr query: start_date" );

    my $tp_start = Time::Piece->strptime( $topic->{ start_date }, '%Y-%m-%d' );
    my $expected_end_date = $tp_start->add_months( 1 )->strftime( '%Y-%m-%d' );
    is( $end_date, $expected_end_date, "full solr query: end_date" );

    my $got_media_ids_list = join( ',', sort( split( ' ', $media_ids_list ) ) );
    my $expected_media_ids = $db->query( "select media_id from topics_media_map where topics_id = ?", $topics_id )->flat;
    my $expected_media_ids_list = join( ',', sort( @{ $expected_media_ids } ) );
    is( $got_media_ids_list, $expected_media_ids_list, "full solr query: media ids" );

    my $got_tags_ids_list = join( ',', sort( split( ' ', $tags_ids_list ) ) );
    my $expected_tags_ids = $db->query( "select tags_id from topics_media_tags_map where topics_id = ?", $topics_id )->flat;
    my $expected_tags_ids_list = join( ',', sort( @{ $expected_tags_ids } ) );
    is( $got_tags_ids_list, $expected_tags_ids_list, "full solr query: media ids" );

    my $offset_full_solr_query = MediaWords::Solr::Query::get_full_solr_query_for_topic( $db, $topic, undef, undef, 1 );
    @fq_matches = $offset_full_solr_query->{ fq } =~
      /publish_day\:\[(\d\d\d\d\-\d\d\-\d\d)T00:00:00Z TO (\d\d\d\d\-\d\d\-\d\d)T23:59:59Z\]/;

    ok( @fq_matches, "offset solr query:  matches expected pattern: $got_full_solr_query->{ fq }" );

    my ( $offset_start_date, $offset_end_date ) = @fq_matches;

    $tp_start = Time::Piece->strptime( $topic->{ start_date }, '%Y-%m-%d' )->add_months( 1 );
    my $expected_start_date = $tp_start->strftime( '%Y-%m-%d' );
    is( $offset_start_date, $expected_start_date, "offset solr query: start_date" );

    $expected_end_date = $tp_start->add_months( 1 )->strftime( '%Y-%m-%d' );
    is( $offset_end_date, $expected_end_date, "offset solr query: end_date" );

    my $undef_full_solr_query = MediaWords::Solr::Query::get_full_solr_query_for_topic( $db, $topic, undef, undef, 3 );
    ok( !$undef_full_solr_query, "solr query offset beyond end date is undef" );
}

sub main()
{
    my $db = MediaWords::DB::connect_to_db();

    test_get_full_solr_query_for_topic( $db );
}

main();

