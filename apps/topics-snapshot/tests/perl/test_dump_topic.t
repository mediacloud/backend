use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Encode;
use Readonly;
use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Topics;
use MediaWords::TM::Dump;
use MediaWords::TM::Snapshot;
use MediaWords::TM::Snapshot::Views;
use MediaWords::Test::DB::Create;
use MediaWords::Util::CSV;
use MediaWords::Util::PublicStore;

Readonly my $NUM_MEDIA => 5;
Readonly my $NUM_STORIES_PER_MEDIUM => 10;


sub validate_file
{
    my ( $table, $db, $row_id, $name, $num_expected_rows ) = @_;

    my $label .= "$table [$row_id] $name";

    my $file = $db->query( <<SQL, $row_id, $name )->hash;
select * from ${table}_files where ${table}s_id = ? and name = ?
SQL

    ok( $file, "$label file exists" );

    my $content_type = "${ table }_files";

    my $object_id = MediaWords::TM::Dump::get_store_object_id( $row_id, $name );

    my $content = MediaWords::Util::PublicStore::fetch_content( $db, $content_type, $object_id );

    if ( $table eq 'timespan' )
    {
        my $got_rows = MediaWords::Util::CSV::get_encoded_csv_as_hashes( $content );

        if ( defined( $num_expected_rows ) )
        {
            is( scalar( @{ $got_rows } ), $num_expected_rows, "$label expected rows" );
        }
        else
        {
            ok( scalar( @{ $got_rows } ) > 0, "$label expected rows" );
        }
    }
    elsif ( $table eq 'snapshot' )
    {
        my $got_lines = 0;
        ++$got_lines while $content =~ /\n/g;

        is( $got_lines, $num_expected_rows );
    }
}

sub validate_timespan_file
{
    validate_file( 'timespan', @_ );
}

sub validate_snapshot_file
{
    validate_file( 'snapshot', @_ );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'foo' );
    MediaWords::Test::DB::Create::create_test_topic_stories( $db, $topic, $NUM_MEDIA, $NUM_STORIES_PER_MEDIUM );

    my $num_posts = MediaWords::Test::DB::Create::create_test_topic_posts( $db, $topic );

    my $num_stories = $NUM_MEDIA * $NUM_STORIES_PER_MEDIUM;

    MediaWords::TM::Snapshot::snapshot_topic( $db, $topic->{ topics_id } );

    my $timespan = $db->query( "select * from timespans where period = 'overall' and foci_id is null" )->hash;

    MediaWords::TM::Snapshot::Views::setup_temporary_snapshot_views( $db, $timespan );

    validate_timespan_file( $db, $timespan->{ timespans_id }, 'stories', $num_stories );
    validate_timespan_file( $db, $timespan->{ timespans_id }, 'media', $NUM_MEDIA );
    validate_timespan_file( $db, $timespan->{ timespans_id }, 'story_links', $num_stories );
    validate_timespan_file( $db, $timespan->{ timespans_id }, 'medium_links' );
    validate_timespan_file( $db, $timespan->{ timespans_id }, 'post_stories', 0 );
    validate_timespan_file( $db, $timespan->{ timespans_id }, 'topic_posts', 0 );

    $db->query( "discard temp" );

    my $post_timespan = $db->query( "select * from timespans where period = 'overall' and foci_id is not null" )->hash;

    MediaWords::TM::Snapshot::Views::setup_temporary_snapshot_views( $db, $post_timespan );

    validate_timespan_file( $db, $post_timespan->{ timespans_id }, 'topic_posts', $num_posts );
    validate_timespan_file( $db, $post_timespan->{ timespans_id }, 'post_stories', $num_posts );

    $db->query( "discard temp" );

    my $snapshot = $db->require_by_id( 'snapshots', $post_timespan->{ snapshots_id } );

    validate_snapshot_file( $db, $snapshot->{ snapshots_id }, 'topic_posts', $num_posts );

    done_testing();
}

main();
