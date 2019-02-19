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
use MediaWords::Test::Types;

Readonly my $NUM_MEDIA            => 3;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 4;

# test that a story has the expected content
sub _test_story_fields($$$)
{
    my ( $db, $story, $label ) = @_;

    my $expected_story = $db->require_by_id( 'stories', $story->{ stories_id } );

    my $fields = [ qw/stories_id url guid language publish_date media_id title collect_date/ ];
    map { is( $story->{ $_ }, $expected_story->{ $_ }, "$label field '$_'" ) } @{ $fields };
}

sub test_stories_cliff($)
{
    my ( $db ) = @_;

    # TODO add infrastructure to actually generate CLIFF and test it

    my $label = "stories/cliff";

    # pick a stories_id that does not exist so that we make the end point just tell us that the
    # end point does not exist instead of triggering a fatal error
    my $stories_id = -1;

    my $r = test_get( '/api/v2/stories/cliff', { stories_id => $stories_id } );

    is( scalar( @{ $r } ),         1,           "$label num stories returned" );
    is( $r->[ 0 ]->{ stories_id }, $stories_id, "$label stories_id" );
    MediaWords::Test::Types::is_integer( $r->[ 0 ]->{ stories_id }, "$label stories_id is_integer" );
    is( $r->[ 0 ]->{ cliff }, "story does not exist", "$label does not exist message" );
}

sub test_stories_is_syndicated_ap($)
{
    my ( $db ) = @_;

    my $label = "stories/is_syndicated_ap";

    my $r = test_get( '/api/v2/stories_public/is_syndicated_ap', { content => 'foo' } );
    is( $r->{ is_syndicated }, 0, "$label: not syndicated" );

    $r = test_get( '/api/v2/stories_public/is_syndicated_ap', { content => '(ap)' } );
    is( $r->{ is_syndicated }, 1, "$label: syndicated" );

}

sub test_stories_nytlabels($)
{
    my ( $db ) = @_;

    # TODO add infrastructure to actually generate NYTLabels and test it

    my $label = "stories/nytlabels";

    # pick a stories_id that does not exist so that we make the end point just tell us that the
    # end point does not exist instead of triggering a fatal error
    my $stories_id = -1;

    my $r = test_get( '/api/v2/stories/nytlabels', { stories_id => $stories_id } );

    is( scalar( @{ $r } ),         1,           "$label num stories returned" );
    is( $r->[ 0 ]->{ stories_id }, $stories_id, "$label stories_id" );
    MediaWords::Test::Types::is_integer( $r->[ 0 ]->{ stories_id }, "$label stories_id is_integer" );
    is( $r->[ 0 ]->{ nytlabels }, "story does not exist", "$label does not exist message" );
}

sub test_stories_list($)
{
    my ( $db ) = @_;

    my $label = "stories/list";

    my $stories = $db->query( <<SQL )->hashes;
select s.*,
        m.name media_name,
        m.url media_url,
        false ap_syndicated
    from stories s
        join media m using ( media_id )
    order by stories_id
    limit 10
SQL

    my $stories_ids_list = join( ' ', map { $_->{ stories_id } } @{ $stories } );

    my $params = {
        q                => "stories_id:( $stories_ids_list )",
        raw_1st_download => 1,
        sentences        => 1,
        text             => 1,
    };

    my $got_stories = test_get( '/api/v2/stories/list', $params );

    my $fields = [ qw/title description publish_date language collect_date ap_syndicated media_id media_name media_url/ ];
    rows_match( $label, $got_stories, $stories, 'stories_id', $fields );

    my $got_stories_lookup = {};
    map { $got_stories_lookup->{ $_->{ stories_id } } = $_ } @{ $got_stories };

    for my $story ( @{ $stories } )
    {
        my $sid       = $story->{ stories_id };
        my $got_story = $got_stories_lookup->{ $story->{ stories_id } };

        my $sentences = $db->query( "select * from story_sentences where stories_id = ?", $sid )->hashes;
        my $download_text = $db->query(
            <<SQL,
            SELECT *
            FROM download_texts
            WHERE downloads_id = (
                SELECT downloads_id
                FROM downloads
                WHERE stories_id = ?
                ORDER BY downloads_id
                LIMIT 1
            )
SQL
            $sid
        )->hash;

        my $content = MediaWords::DBI::Downloads::get_content_for_first_download( $db, $story );

        my $ss_fields = [ qw/is_dup language media_id publish_date sentence sentence_number story_sentences_id/ ];
        rows_match( "$label $sid sentences", $got_story->{ story_sentences }, $sentences, 'story_sentences_id', $ss_fields );

        is( $got_story->{ raw_first_download_file }, $content, "$label $sid download" );
        is( $got_story->{ story_text }, $download_text->{ download_text }, "$label $sid download_text" );
    }

    my $story = $stories->[ 0 ];

    my $got_story = test_get( '/api/v2/stories/single/' . $story->{ stories_id }, {} );
    rows_match( "stories/single", $got_story, [ $story ], 'stories_id', [ qw/stories_id title publish_date/ ] );
}

# various tests to validate stories_public/list
sub test_stories_public_list($$)
{
    my ( $db, $test_media ) = @_;

    my $stories = test_get( '/api/v2/stories_public/list', { q => 'title:story*', rows => 100000 } );

    my $expected_num_stories = $NUM_MEDIA * $NUM_FEEDS_PER_MEDIUM * $NUM_STORIES_PER_FEED;
    my $got_num_stories      = scalar( @{ $stories } );
    is( $got_num_stories, $expected_num_stories, "stories_public/list: number of stories" );

    my $title_stories_lookup = {};
    my $expected_stories = [ grep { $_->{ stories_id } } values( %{ $test_media } ) ];
    map { $title_stories_lookup->{ $_->{ title } } = $_ } @{ $expected_stories };

    for my $i ( 0 .. $expected_num_stories - 1 )
    {
        my $expected_title = "story story_$i";
        my $found_story    = $title_stories_lookup->{ $expected_title };
        ok( $found_story, "found story with title '$expected_title'" );
        _test_story_fields( $db, $stories->[ $i ], "all stories: story $i" );
    }

    my $search_result =
      test_get( '/api/v2/stories_public/list', { q => 'stories_id:' . $stories->[ 0 ]->{ stories_id } } );
    is( scalar( @{ $search_result } ), 1, "stories_public search: count" );
    is( $search_result->[ 0 ]->{ stories_id }, $stories->[ 0 ]->{ stories_id }, "stories_public search: stories_id match" );
    _test_story_fields( $db, $search_result->[ 0 ], "story_public search" );

    my $stories_single = test_get( '/api/v2/stories_public/single/' . $stories->[ 1 ]->{ stories_id } );
    is( scalar( @{ $stories_single } ), 1, "stories_public/single: count" );
    is( $stories_single->[ 0 ]->{ stories_id }, $stories->[ 1 ]->{ stories_id }, "stories_public/single: stories_id match" );
    _test_story_fields( $db, $search_result->[ 0 ], "stories_public/single" );

    # test feeds_id= param

    # expect error when including q= and feeds_id=
    test_get( '/api/v2/stories_public/list', { q => 'foo', feeds_id => 1 }, 1 );

    my $feed =
      $db->query( "select * from feeds where feeds_id in ( select feeds_id from feeds_stories_map ) limit 1" )->hash;
    my $feed_stories =
      test_get( '/api/v2/stories_public/list', { rows => 100000, feeds_id => $feed->{ feeds_id }, show_feeds => 1 } );
    my $expected_feed_stories = $db->query( <<SQL, $feed->{ feeds_id } )->hashes;
select s.* from stories s join feeds_stories_map fsm using ( stories_id ) where feeds_id = ?
SQL

    is( scalar( @{ $feed_stories } ), scalar( @{ $expected_feed_stories } ), "stories feed count feed $feed->{ feeds_id }" );
    for my $feed_story ( @{ $feed_stories } )
    {
        my ( $expected_story ) = grep { $_->{ stories_id } eq $feed_story->{ stories_id } } @{ $expected_feed_stories };
        ok( $expected_story,
            "stories feed story $feed_story->{ stories_id } feed $feed->{ feeds_id } matches expected story" );
        is( scalar( @{ $feed_story->{ feeds } } ), 1, "stories feed one feed returned" );
        for my $field ( qw/name url feeds_id media_id type/ )
        {
            is( $feed_story->{ feeds }->[ 0 ]->{ $field }, $feed->{ $field }, "feed story field $field" );
        }
    }
}

sub test_stories_single($)
{
    my ( $db ) = @_;

    my $label = "stories/list";

    my $story = $db->query( <<SQL )->hash;
select s.*,
        m.name media_name,
        m.url media_url,
        false ap_syndicated
    from stories s
        join media m using ( media_id )
    order by stories_id
    limit 1
SQL

    my $got_stories = test_get( '/api/v2/stories/list', { q => "stories_id:$story->{ stories_id }" } );

    my $fields = [ qw/title description publish_date language collect_date ap_syndicated media_id media_name media_url/ ];
    rows_match( $label, $got_stories, [ $story ], 'stories_id', $fields );
}

sub test_stories_count($)
{
    my ( $db ) = @_;

    my $stories = $db->query( "select * from stories order by stories_id asc limit 23" )->hashes;

    my $stories_ids_list = join( ' ', map { $_->{ stories_id } } @{ $stories } );

    my $r = test_get( '/api/v2/stories/count', { q => "stories_id:($stories_ids_list)" } );

    is( $r->{ count }, scalar( @{ $stories } ), "stories/count count" );

    $r = test_get( '/api/v2/stories_public/count', { q => "stories_id:($stories_ids_list)" } );

    is( $r->{ count }, scalar( @{ $stories } ), "stories/count count" );
}

sub test_stories_count_split($)
{
    my ( $db ) = @_;

    my $label = "stories/count split";

    $db->query( <<SQL );
update stories set publish_date = '2017-01-01'::date + ( ( stories_id % 27 )::text || ' days' )::interval
SQL

    MediaWords::Solr::Dump::import_data( $db, { throttle => 0 } );

    my $date_counts = $db->query( "select publish_date, count(*) as count from stories group by publish_date" )->hashes;

    my $date_count_lookup = {};
    map { $date_count_lookup->{ $_->{ publish_date } } = $_->{ count } } @{ $date_counts };

    my $params = {
        q     => '*:*',
        split => 1,
    };

    my $r = test_get( '/api/v2/stories/count', $params );

    my $got_date_counts = $r->{ date_counts };
    for my $got_date_count ( @{ $got_date_counts } )
    {
        my $got_date  = $got_date_count->{ date };
        my $got_count = $got_date_count->{ count };

        $got_date =~ /(\d\d\d\d-\d\d-\d\d)/ || die( "Unable to parse api returned date: '$got_date'" );

        my $expected_date = "$1 00:00:00";

        my $expected_count = $date_count_lookup->{ $expected_date } || 0;

        is( $got_count, $expected_count, "$label: date count for $got_date" );
    }

}

sub test_stories_word_matrix($)
{
    my ( $db ) = @_;

    my $label = "stories/word_matrix";

    my $stories          = $db->query( "select * from stories order by stories_id limit 17" )->hashes;
    my $stories_ids      = [ map { $_->{ stories_id } } @{ $stories } ];
    my $stories_ids_list = join( ' ', @{ $stories_ids } );

    # this functionality is already tested in test_get_story_word_matrix(), so we're just makingn sure no errors
    # are generated and the return format is correct

    my $r = test_get( '/api/v2/stories/word_matrix', { q => "stories_id:( $stories_ids_list )" } );
    ok( $r->{ word_matrix }, "$label word matrix present" );
    ok( $r->{ word_list },   "$label word list present" );

    $r = test_get( '/api/v2/stories_public/word_matrix', { q => "stories_id:( $stories_ids_list )" } );
    ok( $r->{ word_matrix }, "$label word matrix present" );
    ok( $r->{ word_list },   "$label word list present" );
}

sub test_stories_update($$)
{
    my ( $db ) = @_;

    # test that request with no stories_id returns an error
    test_put( '/api/v2/stories/update', {}, 1 );

    # test that request with list returns an error
    test_put( '/api/v2/stories/update', { stories_id => 1 }, 1 );

    my $media = MediaWords::Test::DB::Create::create_test_story_stack( $db,
        { 'update_m1' => { 'update_f1' => [ 'update_s1', 'update_s2', 'update_s3' ] } } );

    my $story = $media->{ update_s1 };

    my $story_data = {};

    $story_data->{ stories_id } = $story->{ stories_id };

    # my $text_fields = [ qw/title url guid description/ ];
    my $text_fields = [ qw/description/ ];
    map { $story_data->{ $_ } = $story->{ $_ } . "_update_$_" } @{ $text_fields };

    $story_data->{ publish_date } = '2015-06-01 01:09:01';
    $story_data->{ language }     = 'zz';
    $story_data->{ confirm_date } = 1;
    $story_data->{ undateable }   = 1;

    my $r = test_put( '/api/v2/stories/update', $story_data );
    is( $r->{ success }, 1, "stories/update all success" );

    my $updated_story = $db->require_by_id( 'stories', $story->{ stories_id } );

    $updated_story->{ confirm_date } = MediaWords::DBI::Stories::GuessDate::date_is_confirmed( $db, $updated_story );
    $updated_story->{ undateable } = MediaWords::DBI::Stories::GuessDate::is_undateable( $db, $updated_story );

    my $all_fields = [ @{ $text_fields }, 'publish_date', 'language', 'confirm_date', 'undateable' ];
    map { is( $updated_story->{ $_ }, $story_data->{ $_ }, "story update field $_" ) } @{ $all_fields };
}

sub test_stories_field_count($)
{
    my ( $db ) = @_;

    my $label = "stories/field_count";

    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "$label:$label" );

    my $stories = $db->query( "select * from stories order by stories_id asc limit 10" )->hashes;
    my $tagged_stories = [ ( @{ $stories } )[ 1 .. 5 ] ];
    for my $story ( @{ $tagged_stories } )
    {
        $db->query( <<SQL, $story->{ stories_id }, $tag->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
SQL
    }

    my $stories_ids = [ map { $_->{ stories_id } } @{ $stories } ];
    my $stories_ids_list = join( ' ', @{ $stories_ids } );

    my $tagged_stories_ids = [ map { $_->{ stories_id } } @{ $tagged_stories } ];

    my $r = test_get( '/api/v2/stories/field_count',
        { field => 'tags_id_stories', q => "stories_id:($stories_ids_list)", tag_sets_id => $tag->{ tag_sets_id } } );

    is( scalar( @{ $r } ), 1, "$label num of tags" );

    my $got_tag = $r->[ 0 ];
    is( $got_tag->{ count }, scalar( @{ $tagged_stories } ), "$label count" );
    map { is( $got_tag->{ $_ }, $tag->{ $_ }, "$label field '$_'" ) } ( qw/tag tags_id label tag_sets_id/ );
}

sub test_stories($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    $media = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    test_stories_cliff( $db );
    test_stories_nytlabels( $db );
    test_stories_list( $db );
    test_stories_single( $db );
    test_stories_public_list( $db, $media );
    test_stories_count( $db );
    test_stories_count_split( $db );
    test_stories_word_matrix( $db );
    test_stories_update( $db, $media );
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_stories,
        [ 'solr_standalone', 'job_broker:rabbitmq', 'rescrape_media' ] );

    done_testing();
}

main();
