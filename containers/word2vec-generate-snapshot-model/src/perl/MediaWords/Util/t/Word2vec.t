use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More tests => 3;
use Test::NoWarnings;
use Test::Deep;

use Readonly;

use MediaWords::Test::DB;
use MediaWords::KeyValueStore::PostgreSQL;
use MediaWords::Util::Word2vec;

sub test_load_word2vec_model($)
{
    my $db = shift;

    my $topic = MediaWords::Test::DB::create_test_topic( $db, 'test' );
    my $topics_id = $topic->{ topics_id };

    my $snapshot = $db->create(
        'snapshots',
        {
            topics_id     => $topics_id,
            snapshot_date => '2017-01-01',
            start_date    => '2016-01-01',
            end_date      => '2017-01-01',
        }
    );
    my $snapshots_id = $snapshot->{ snapshots_id };

    my $expected_model_data = "\x00\x01\x02";

    # Snapshot
    {
        my $model_row = $db->create( 'snap.word2vec_models', { 'object_id' => $topics_id } );
        my $models_id = $model_row->{ $db->primary_key_column( 'snap.word2vec_models' ) };

        my $postgresql_store = MediaWords::KeyValueStore::PostgreSQL->new( { table => 'snap.word2vec_models_data' } );
        $postgresql_store->store_content( $db, $snapshots_id, $expected_model_data );

        my $model_store = MediaWords::Util::Word2vec::SnapshotDatabaseModelStore->new( $db, $snapshots_id );
        my $got_model_data = MediaWords::Util::Word2vec::load_word2vec_model( $model_store, $models_id );
        ok( defined $got_model_data );
        is( $got_model_data, $expected_model_data );
    }
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_load_word2vec_model( $db );
        }
    );
}

main();
