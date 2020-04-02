# test that the timespan field gets exported to solr

use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Topics;
use MediaWords::TM::Snapshot;
use MediaWords::Test::Solr;
use MediaWords::Job::Broker;
use MediaWords::Test::DB::Create;
use MediaWords::DB::Snapshot;

sub test_timespan_export($)
{
    my ( $db ) = @_;

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

    my $num_solr_stories = MediaWords::Solr::get_solr_num_found( $db, { q => '*:*' } );
    ok( $num_solr_stories > 0, "total number of solr stories is greater than 0" );

    my $topic_media_id = $media->{ medium_1 }->{ media_id };

    my $num_topic_medium_stories = MediaWords::Solr::get_solr_num_found( $db, { q => "media_id:$topic_media_id" } );
    ok( $num_topic_medium_stories > 0, "number of topic medium stories is greater than 0" );

    $db->query( <<SQL, $topic->{ topics_id }, $topic_media_id );
insert into topic_stories ( topics_id, stories_id )
    select \$1, stories_id from stories where media_id = \$2
SQL

    MediaWords::TM::Snapshot::snapshot_topic( $db, $topic->{ topics_id } );

    $num_solr_stories = MediaWords::Solr::get_solr_num_found( $db, { q => 'timespans_id:1' } );
    is( $num_solr_stories, 0, "number of solr stories before snapshot import" );

    my ( $num_solr_exported_stories ) = $db->query( "select count(*) from solr_import_stories" )->flat;
    $num_topic_medium_stories = scalar( values( %{ $media->{ medium_1 }->{ feeds }->{ feed_1 }->{ stories } } ) );
    is( $num_solr_exported_stories, $num_topic_medium_stories, "number of stories added to solr export queue" );

    my $timespan = MediaWords::DBI::Topics::get_latest_overall_timespan( $db, $topic->{ topics_id } );

    MediaWords::Job::Broker->new( 'MediaWords::Job::ImportSolrDataForTesting' )->run_remotely( { empty_queue => 1 } );

    my $num_topic_stories = MediaWords::Solr::get_solr_num_found( $db, { q => "timespans_id:$timespan->{ timespans_id }" } );
    is( $num_topic_stories, $num_topic_medium_stories, "topic stories after snapshot" );

    my $focus_stories_id = $media->{ story_1 }->{ stories_id };

    my $fsd = $db->create( 'focal_set_definitions',
        { topics_id => $topic->{ topics_id }, name => 'test', focal_technique => 'Boolean Query' } );

    $db->query( <<SQL, 'test', 'test', "stories_id:$focus_stories_id", $fsd->{ focal_set_definitions_id } );
insert into focus_definitions ( name, description, arguments, focal_set_definitions_id )
    select \$1, \$2, ( '{ "query": ' || to_json( \$3::text ) || ' }' )::json, \$4
SQL

    MediaWords::TM::Snapshot::snapshot_topic( $db, $topic->{ topics_id } );

    MediaWords::Job::Broker->new( 'MediaWords::Job::ImportSolrDataForTesting' )->run_remotely( { empty_queue => 1 } );

    my ( $focus_timespans_id ) = $db->query( <<SQL )->flat;
select *
    from timespans t
    where
        t.foci_id is not null and
        t.period = 'overall'
    order by timespans_id desc limit 1
SQL

    my $focus_story_stories    = MediaWords::Solr::get_solr_num_found( $db, { q => "stories_id:$focus_stories_id" } );
    my $focus_timespan_stories = MediaWords::Solr::get_solr_num_found( $db, { q => "timespans_id:$focus_timespans_id" } );

    is( $focus_timespan_stories, $focus_story_stories, "focus timespan stories" );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_timespan_export( $db );

    done_testing();
}

main();
