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

    my $got_foci = MediaWords::TM::Snapshot::_create_url_sharing_foci( $db, $snapshot );

    is( scalar( @{ $got_foci } ), $num_seed_queries );

    for my $focus ( @{ $got_foci } )
    {
        my $timespan = MediaWords::Test::DB::Create::create_test_timespan( $db, $snapshot );
        $timespan = $db->update_by_id( 'timespans', $timespan->{ timespans_id }, { foci_id => $focus->{ foci_id } } );

        my $got_topic_seed_queries_id = MediaWords::TM::Snapshot::_get_timespan_seed_query( $db, $timespan );

        my $arguments = MediaWords::Util::ParseJSON::decode_json( $focus->{ arguments } );
        is( $got_topic_seed_queries_id, $arguments->{ topic_seed_queries_id } );
    }

    done_testing();
}

main();
