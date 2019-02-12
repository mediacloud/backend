#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use MediaWords::CommonLibs;
use MediaWords::Solr::Query::PseudoQueries;
use MediaWords::Test::DB;
use MediaWords::Test::DB::Create;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;
use MediaWords::Job::TM::SnapshotTopic;

sub test_consolidate_id_query()
{
    is(
        MediaWords::Solr::Query::PseudoQueries::_consolidate_id_query( 'stories_id', [ 1, 2, 4, 5, 6, 7, 9 ] ),    #
        'stories_id:[4 TO 7] stories_id:(9 1 2)',                                                                  #
    );

    is(
        MediaWords::Solr::Query::PseudoQueries::_consolidate_id_query( 'stories_id', [ 11 ] ),                     #
        'stories_id:(11)',                                                                                         #
    );

    is(
        MediaWords::Solr::Query::PseudoQueries::_consolidate_id_query( 'stories_id', [ 1, 2 ] ),                   #
        'stories_id:(1 2)',                                                                                        #
    );

    is(
        MediaWords::Solr::Query::PseudoQueries::_consolidate_id_query( 'stories_id', [ '11' ] ),                   #
        'stories_id:(11)',                                                                                         #
    );
}

sub test_transform_query($)
{
    my $db = shift;

    is( MediaWords::Solr::Query::PseudoQueries::transform_query( $db, undef ),         undef );
    is( MediaWords::Solr::Query::PseudoQueries::transform_query( $db, '' ),            '' );
    is( MediaWords::Solr::Query::PseudoQueries::transform_query( $db, 'foo' ),         'foo' );
    is( MediaWords::Solr::Query::PseudoQueries::transform_query( $db, 'foo and bar' ), 'foo and bar' );

    eval { MediaWords::Solr::Query::PseudoQueries::transform_query( $db, '{~}' ); };
    ok( $@ );

    eval { MediaWords::Solr::Query::PseudoQueries::transform_query( $db, '{~foo:arg1}' ); };
    ok( $@ );

    eval { MediaWords::Solr::Query::PseudoQueries::transform_query( $db, '{~foo:arg1-arg2-arg3}' ); };
    ok( $@ );

    my $media = MediaWords::Test::DB::Create::create_test_story_stack(
        $db,
        {
            medium_1 => { feed_1 => [ map { "story_$_" } ( 1 .. 10 ) ] },
            medium_2 => { feed_2 => [ map { "story_$_" } ( 11 .. 20 ) ] },
            medium_3 => { feed_3 => [ map { "story_$_" } ( 21 .. 30 ) ] },
        }
    );
    $media = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $db, $media );

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'foo' );

    MediaWords::Test::Solr::setup_test_index( $db );

    my $topic_media_id = $media->{ medium_1 }->{ media_id };

    $db->query(
        <<SQL,
        INSERT INTO topic_stories (topics_id, stories_id)
            SELECT ?, stories_id
            FROM stories
            WHERE media_id = ?
SQL
        $topic->{ topics_id }, $topic_media_id
    );

    MediaWords::Job::TM::SnapshotTopic->run_locally( { topics_id => $topic->{ topics_id } } );

    my $timespan = MediaWords::TM::get_latest_overall_timespan( $db, $topic->{ topics_id } );
    my $timespans_id = $timespan->{ timespans_id };

    my $timespan_story_ids = $db->query(
        <<SQL,
        SELECT stories_id
        FROM snap.story_link_counts
        WHERE timespans_id = ?
        ORDER BY stories_id
SQL
        $timespans_id
    )->flat;
    ok( scalar( @{ $timespan_story_ids } ) > 4 );

    # _transform_link_to_story_field
    {
        my $stories_id_1 = $timespan_story_ids->[ 0 ];
        my $stories_id_2 = $timespan_story_ids->[ 1 ];

        $db->query(
            <<SQL,
            INSERT INTO snap.story_links (timespans_id, source_stories_id, ref_stories_id)
            VALUES (?, ?, ?)
SQL
            $timespans_id, $stories_id_1, $stories_id_2
        );
        my $q = "{~link_to_story:$stories_id_2 timespan:$timespans_id}";
        my $transformed_q = MediaWords::Solr::Query::PseudoQueries::transform_query( $db, $q );
        is( $transformed_q, "stories_id:($stories_id_1)" );
    }

    # _transform_link_from_story_field
    {
        my $stories_id_1 = $timespan_story_ids->[ 2 ];
        my $stories_id_2 = $timespan_story_ids->[ 3 ];

        $db->query(
            <<SQL,
            INSERT INTO snap.story_links (timespans_id, source_stories_id, ref_stories_id)
            VALUES (?, ?, ?)
SQL
            $timespans_id, $stories_id_1, $stories_id_2
        );
        my $q = "{~link_from_story:$stories_id_1 timespan:$timespans_id}";
        my $transformed_q = MediaWords::Solr::Query::PseudoQueries::transform_query( $db, $q );
        is( $transformed_q, "stories_id:($stories_id_2)" );
    }

    # _transform_link_to_medium_field
    {
        # Only a single test timespan, no need for WHERE
        my $expected_stories_ids = $db->query(
            <<SQL
            SELECT DISTINCT sl.source_stories_id
            FROM snap.stories AS s
                JOIN snap.story_links AS sl
                    ON sl.ref_stories_id = s.stories_id
            ORDER BY sl.source_stories_id
SQL
        )->flat;
        my $q = "{~link_to_medium:$topic_media_id timespan:$timespans_id}";
        my $transformed_q = MediaWords::Solr::Query::PseudoQueries::transform_query( $db, $q );
        is( $transformed_q, "stories_id:(" . join( ' ', @{ $expected_stories_ids } ) . ")" );
    }

    # _transform_link_from_medium_field
    {
        # Only a single test timespan, no need for WHERE
        my $expected_stories_ids = $db->query(
            <<SQL
            SELECT DISTINCT sl.ref_stories_id
            FROM snap.stories AS s
                JOIN snap.story_links AS sl
                    ON sl.source_stories_id = s.stories_id
            ORDER BY sl.ref_stories_id
SQL
        )->flat;
        my $q = "{~link_from_medium:$topic_media_id timespan:$timespans_id}";
        my $transformed_q = MediaWords::Solr::Query::PseudoQueries::transform_query( $db, $q );
        is( $transformed_q, "stories_id:(" . join( ' ', @{ $expected_stories_ids } ) . ")" );
    }

    # _transform_topic_field
    {
        my $topics_id = $topic->{ topics_id };

        my $min_max_stories_id = $db->query(
            <<SQL,
            SELECT
                MIN(stories_id) AS min,
                MAX(stories_id) AS max
            FROM topic_stories
            WHERE topics_id = ?
SQL
            $topics_id
        )->hash;
        my $min_stories_id = $min_max_stories_id->{ min };
        my $max_stories_id = $min_max_stories_id->{ max };

        my $q = "{~topic:$topics_id timespan:$timespans_id}";
        my $transformed_q = MediaWords::Solr::Query::PseudoQueries::transform_query( $db, $q );
        is( $transformed_q, "stories_id:[$min_stories_id TO $max_stories_id]" );
    }

    # _transform_timespan_field
    {
        my $min_max_stories_id = $db->query(
            <<SQL,
            SELECT
                MIN(stories_id) AS min,
                MAX(stories_id) AS max
            FROM snap.story_link_counts
            WHERE timespans_id = ?
SQL
            $timespans_id
        )->hash;
        my $min_stories_id = $min_max_stories_id->{ min };
        my $max_stories_id = $min_max_stories_id->{ max };

        my $q = "{~timespan:$timespans_id}";
        my $transformed_q = MediaWords::Solr::Query::PseudoQueries::transform_query( $db, $q );
        is( $transformed_q, "stories_id:[$min_stories_id TO $max_stories_id]" );
    }

    # _transform_link_from_tag_field with integer parameter
    {
        my $tags_ids = $db->query(
            <<SQL
            SELECT tags_id
            FROM snap.tags
            ORDER BY tags_id
SQL
        )->flat;
        ok( scalar( @{ $tags_ids } ) > 0 );
        my $tags_id = $tags_ids->[ 0 ];

        my $expected_stories_ids = $db->query(
            <<SQL,
            WITH tagged_stories AS (
                SELECT
                    stm.stories_id,
                    stm.tags_id
                FROM snap.stories_tags_map AS stm

                UNION

                SELECT
                    s.stories_id,
                    mtm.tags_id
                    FROM snap.stories AS s
                        JOIN media_tags_map AS mtm
                            ON s.media_id = mtm.media_id

            )

            SELECT sl.ref_stories_id
            FROM snap.story_links AS sl
            WHERE
                sl.source_stories_id IN (
                    SELECT stories_id
                    FROM tagged_stories AS ts
                    WHERE ts.tags_id = ?
                )
SQL
            $tags_id
        )->flat;

        {
            my $q = "{~link_from_tag:$tags_id timespan:$timespans_id}";
            my $transformed_q = MediaWords::Solr::Query::PseudoQueries::transform_query( $db, $q );
            is( $transformed_q,
                MediaWords::Solr::Query::PseudoQueries::_consolidate_id_query( 'stories_id', $expected_stories_ids ) );
        }

        {
            my $q = "{~link_from_tag:$tags_id-$tags_id timespan:$timespans_id}";
            my $transformed_q = MediaWords::Solr::Query::PseudoQueries::transform_query( $db, $q );
            is( $transformed_q,
                MediaWords::Solr::Query::PseudoQueries::_consolidate_id_query( 'stories_id', $expected_stories_ids ) );
        }

        {
            my $q = "{~link_from_tag:$tags_id-other timespan:$timespans_id}";
            my $transformed_q = MediaWords::Solr::Query::PseudoQueries::transform_query( $db, $q );
            is( $transformed_q,
                MediaWords::Solr::Query::PseudoQueries::_consolidate_id_query( 'stories_id', $expected_stories_ids ) );
        }
    }
}

sub main
{
    test_consolidate_id_query();

    MediaWords::Test::Supervisor::test_with_supervisor( \&test_transform_query,
        [ 'solr_standalone', 'job_broker:rabbitmq' ] );

    done_testing();
}

main();
