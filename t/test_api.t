#!/usr/bin/env perl

# general test of api end popints

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";

}

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use HTTP::HashServer;
use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::DBI::Media::Health;
use MediaWords::DBI::Stats;
use MediaWords::Test::API;
use MediaWords::Test::DB;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;
use MediaWords::Util::Tags;
use MediaWords::Util::Web;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

# test wc/list end point
sub test_wc_list($)
{
    my ( $db ) = @_;

    my $label = "wc/list";

    my $story = $db->query( "select * from stories order by stories_id limit 1" )->hash;

    my $sentences = $db->query( <<SQL, $story->{ stories_id } )->flat;
select sentence from story_sentences where stories_id = ?
SQL

    my $en = MediaWords::Languages::Language::language_for_code( 'en' );

    my $expected_word_counts = {};
    for my $sentence ( @{ $sentences } )
    {
        my $words = [ grep { length( $_ ) > 2 } split( /\W+/, lc( $sentence ) ) ];
        my $stems = $en->stem( @{ $words } );
        map { $expected_word_counts->{ $_ }++ } @{ $stems };
    }

    my $got_word_counts = test_get(
        '/api/v2/wc/list',
        {
            q                 => "stories_id:$story->{ stories_id }",
            languages         => 'en',                                 # set to english so that we can know how to stem above
            num_words         => 10000,
            include_stopwords => 1                                     # don't try to test stopwording
        }
    );

    is( scalar( @{ $got_word_counts } ), scalar( keys( %{ $expected_word_counts } ) ), "$label number of words" );

    for my $got_word_count ( @{ $got_word_counts } )
    {
        my $stem = $got_word_count->{ stem };
        ok( $expected_word_counts->{ $stem }, "$label word count for '$stem' is found but not expected" );
        is( $got_word_count->{ count }, $expected_word_counts->{ $stem }, "$label expected word count for '$stem'" );
    }
}

# test controversies/list and single
sub test_controversies($)
{
    my ( $db ) = @_;

    my $label = "controversies/list";

    map { MediaWords::Test::DB::create_test_topic( $db, "$label $_" ) } ( 1 .. 10 );

    my $expected_topics = $db->query( "select *, topics_id controversies_id from topics" )->hashes;

    my $got_controversies = test_get( '/api/v2/controversies/list', {} );

    my $fields = [ qw/controversies_id name pattern solr_seed_query description max_iterations/ ];
    rows_match( $label, $got_controversies, $expected_topics, "controversies_id", $fields );

    $label = "controversies/single";

    my $expected_single = $expected_topics->[ 0 ];

    my $got_controversy = test_get( '/api/v2/controversies/single/' . $expected_single->{ topics_id }, {} );
    rows_match( $label, $got_controversy, [ $expected_single ], 'controversies_id', $fields );
}

# test controversy_dumps/list and single
sub test_controversy_dumps($)
{
    my ( $db ) = @_;

    my $label = "controversy_dumps/list";

    my $topic = MediaWords::Test::DB::create_test_topic( $db, $label );

    for my $i ( 1 .. 10 )
    {
        $db->create(
            'snapshots',
            {
                topics_id     => $topic->{ topics_id },
                snapshot_date => '2017-01-01',
                start_date    => '2016-01-01',
                end_date      => '2017-01-01',
                note          => "snapshot $i"
            }
        );
    }

    my $expected_snapshots = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select *, topics_id controversies_id, snapshots_id controversy_dumps_id
    from snapshots
    where topics_id = ?
SQL

    my $got_cds = test_get( '/api/v2/controversy_dumps/list', { controversies_id => $topic->{ topics_id } } );

    my $fields = [ qw/controversies_id controversy_dumps_id start_date end_date note/ ];
    rows_match( $label, $got_cds, $expected_snapshots, 'controversy_dumps_id', $fields );

    $label = 'controversy_dumps/single';

    my $expected_snapshot = $expected_snapshots->[ 0 ];

    my $got_cd = test_get( '/api/v2/controversy_dumps/single/' . $expected_snapshot->{ snapshots_id }, {} );
    rows_match( $label, $got_cd, [ $expected_snapshot ], 'controversy_dumps_id', $fields );
}

# test controversy_dump_time_slices/list and single
sub test_controversy_dump_time_slices($)
{
    my ( $db ) = @_;

    my $label = "controversy_dump_time_slices/list";

    my $topic = MediaWords::Test::DB::create_test_topic( $db, $label );
    my $snapshot = $db->create(
        'snapshots',
        {
            topics_id     => $topic->{ topics_id },
            snapshot_date => '2017-01-01',
            start_date    => '2016-01-01',
            end_date      => '2017-01-01',
        }
    );

    my $metrics = [
        qw/story_count story_link_count medium_count medium_link_count tweet_count /,
        qw/model_num_media model_r2_mean model_r2_stddev/
    ];
    for my $i ( 1 .. 9 )
    {
        my $timespan = {
            snapshots_id => $snapshot->{ snapshots_id },
            start_date   => '2016-01-0' . $i,
            end_date     => '2017-01-0' . $i,
            period       => 'custom'
        };

        map { $timespan->{ $_ } = $i * length( $_ ) } @{ $metrics };
        $db->create( 'timespans', $timespan );
    }

    my $expected_timespans = $db->query( <<SQL, $snapshot->{ snapshots_id } )->hashes;
select *, snapshots_id controversy_dumps_id, timespans_id controversy_dump_time_slices_id
    from timespans
    where snapshots_id = ?
SQL

    my $got_cdtss =
      test_get( '/api/v2/controversy_dump_time_slices/list', { controversy_dumps_id => $snapshot->{ snapshots_id } } );

    my $fields = [ qw/controversy_dumps_id start_date end_date period/, @{ $metrics } ];
    rows_match( $label, $got_cdtss, $expected_timespans, 'controversy_dump_time_slices_id', $fields );

    $label = 'controversy_dump_time_slices/single';

    my $expected_timespan = $expected_timespans->[ 0 ];

    my $got_cdts = test_get( '/api/v2/controversy_dump_time_slices/single/' . $expected_timespan->{ timespans_id }, {} );
    rows_match( $label, $got_cdts, [ $expected_timespan ], 'controversy_dump_time_slices_id', $fields );
}

# test mediahealth/list and single
sub test_mediahealth($)
{
    my ( $db ) = @_;

    my $label = "mediahealth/list";

    my $metrics = [
        qw/num_stories num_stories_w num_stories_90 num_stories_y num_sentences num_sentences_w/,
        qw/num_sentences_90 num_sentences_y expected_stories expected_sentences coverage_gaps/
    ];
    for my $i ( 1 .. 10 )
    {
        my $medium = MediaWords::Test::DB::create_test_medium( $db, "$label $i" );
        my $mh = {
            media_id        => $medium->{ media_id },
            is_healthy      => ( $medium->{ media_id } % 2 ) ? 't' : 'f',
            has_active_feed => ( $medium->{ media_id } % 2 ) ? 't' : 'f',
            start_date      => '2011-01-01',
            end_date        => '2017-01-01'
        };

        map { $mh->{ $_ } = $i * length( $_ ) } @{ $metrics };

        $db->create( 'media_health', $mh );
    }

    my $expected_mhs = $db->query( <<SQL, $label )->hashes;
select mh.* from media_health mh join media m using ( media_id ) where m.name like ? || '%'
SQL

    my $media_id_params = join( '&', map { "media_id=$_->{ media_id }" } @{ $expected_mhs } );

    my $got_mhs = test_get( '/api/v2/mediahealth/list?' . $media_id_params, {} );

    my $fields = [ qw/media_id is_health has_active_feed start_date end_date/, @{ $metrics } ];
    rows_match( $label, $got_mhs, $expected_mhs, 'media_id', $fields );
}

sub test_stats_list($)
{
    my ( $db ) = @_;

    my $label = "stats/list";

    MediaWords::DBI::Stats::refresh_stats( $db );

    my $ms = $db->query( "select * from mediacloud_stats" )->hash;

    my $r = test_get( '/api/v2/stats/list', {} );

    my $fields = [
        qw/stats_date daily_downloads daily_stories active_crawled_media active_crawled_feeds/,
        qw/total_stories total_downloads total_sentences/
    ];

    map { is( $r->{ $_ }, $ms->{ $_ }, "$label field '$_'" ) } @{ $fields };
}

# test whether we have at least requested every api end point outside of topics/
sub test_coverage()
{
    my $untested_urls = MediaWords::Test::API::get_untested_api_urls();

    $untested_urls = [ grep { $_ !~ m~/topics/~ } @{ $untested_urls } ];

    ok( scalar( @{ $untested_urls } ) == 0, "end points not requested: " . join( ', ', @{ $untested_urls } ) );
}

# test parts of the ai that only require reading, so we can test these all in one chunk
sub test_api($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    MediaWords::Test::DB::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    test_controversies( $db );
    test_controversy_dumps( $db );
    test_controversy_dump_time_slices( $db );

    test_mediahealth( $db );

    test_wc_list( $db );

    test_stats_list( $db );

    test_coverage();
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_api,
        [ 'solr_standalone', 'job_broker:rabbitmq', 'rescrape_media' ] );

    done_testing();
}

main();
