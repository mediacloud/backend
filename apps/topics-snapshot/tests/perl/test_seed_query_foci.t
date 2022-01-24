# test that the timespan field gets exported to solr

use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::TM::Snapshot;
use MediaWords::Test::DB::Create;
use MediaWords::Util::ParseJSON;

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'foo' );
    my $snapshot = MediaWords::Test::DB::Create::create_test_snapshot( $db, $topic );

    my $num_seed_queries = 3;
    my $topic_seed_queries = [];
    for my $i ( 1 .. $num_seed_queries )
    {
        my $topic_seed_query = {
            topics_id => $topic->{ topics_id },
            platform => 'generic_post',
            source => 'csv',
            query => 'foo'
        };
        push( @{ $topic_seed_queries }, $db->create( 'topic_seed_queries', $topic_seed_query ) );
    }

    MediaWords::TM::Snapshot::_generate_period_foci( $db, $snapshot );

    my $got_fds = $db->query( <<SQL
        SELECT focus_definitions.*
        FROM focus_definitions
            INNER JOIN focal_set_definitions ON
                focus_definitions.topics_id = focal_set_definitions.topics_id AND
                focus_definitions.focal_set_definitions_id = focal_set_definitions.focal_set_definitions_id
        WHERE focal_technique = 'URL Sharing'
SQL
    )->hashes();

    is( scalar( @{ $got_fds } ), $num_seed_queries );

    my $got_foci = $db->query( <<SQL
        SELECT foci.*
        FROM foci
            INNER JOIN focal_sets ON
                foci.topics_id = focal_sets.topics_id AND
                foci.focal_sets_id = focal_sets.topics_id
        WHERE focal_sets.focal_technique = 'URL Sharing'
SQL
    )->hashes();

    is( scalar( @{ $got_foci } ), $num_seed_queries );

    for my $focus ( @{ $got_foci } )
    {
        my $timespan = MediaWords::Test::DB::Create::create_test_timespan( $db, $snapshot );
        $timespan = $db->update_by_id( 'timespans', $timespan->{ timespans_id }, { foci_id => $focus->{ foci_id } } );

        my $got_topic_seed_queries_id = MediaWords::TM::Snapshot::_get_timespan_seed_query( $db, $timespan );

        # FIXME in a sharded database this is always pre-decoded
        my $arguments;
        if ( ref( $focus->{ arguments } ) eq ref( {} ) ) {
            $arguments = $focus->{ arguments };
        } else {
            $arguments = MediaWords::Util::ParseJSON::decode_json( $focus->{ arguments } );
        }

        is( $got_topic_seed_queries_id, $arguments->{ topic_seed_queries_id } );
    }

    done_testing();
}

main();
