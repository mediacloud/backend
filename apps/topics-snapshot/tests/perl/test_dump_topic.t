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

Readonly my $NUM_MEDIA => 5;
Readonly my $NUM_STORIES_PER_MEDIUM => 10;


sub validate_timespan_file
{
    my ( $db, $timespan, $name, $num_expected_rows ) = @_;

    my $label = $timespan->{ foci_id } ? "url sharing timespan" : "overall timespan";

    $label .= " $name";

    my $timespan_file = $db->query( <<SQL, $timespan->{ timespans_id }, $name )->hash;
select * from timespan_files where timespans_id = ? and name = ?
SQL

    ok( $timespan_file, "$label file exists" );
    
    my $ua = MediaWords::Util::Web::UserAgent->new();

    my $response = $ua->get( $timespan_file->{ url } );

    ok( $response->is_success, "$label url response is success" );

    my $content = $response->decoded_content();
    my $encoded_content = Encode::encode( 'utf-8', $content );

    my $got_rows = MediaWords::Util::CSV::get_encoded_csv_as_hashes( $encoded_content );

    if ( defined( $num_expected_rows ) )
    {
        is( scalar( @{ $got_rows } ), $num_expected_rows, "$label expected rows" );
    }
    else
    {
        ok( scalar( @{ $got_rows } ) > 0, "$label expected rows" );
    }
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

    MediaWords::TM::Dump::dump_timespan( $db, $timespan );

    validate_timespan_file( $db, $timespan, 'stories', $num_stories );
    validate_timespan_file( $db, $timespan, 'media', $NUM_MEDIA );
    validate_timespan_file( $db, $timespan, 'story_links', $num_stories );
    validate_timespan_file( $db, $timespan, 'medium_links' );
    validate_timespan_file( $db, $timespan, 'post_stories', 0 );
    validate_timespan_file( $db, $timespan, 'topic_posts', 0 );

    my $post_timespan = $db->query( "select * from timespans where period = 'overall' and foci_id is not null" )->hash;

    MediaWords::TM::Dump::dump_timespan( $db, $post_timespan );

    validate_timespan_file( $db, $post_timespan, 'topic_posts', $num_posts );
    validate_timespan_file( $db, $post_timespan, 'post_stories', $num_posts );

    done_testing();
}

main();
