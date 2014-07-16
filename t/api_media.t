use strict;
use warnings;

#use Test::More;
# use Test::More tests => 4;
# use MediaWords::Test::DB;
# use MediaWords::Test::Data;
# use MediaWords::Test::LocalServer;

use Test::More;

BEGIN
{
    $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;
    use_ok 'Catalyst::Test', 'MediaWords';
}

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
    $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;
    use_ok 'Catalyst::Test', 'MediaWords';
}


use Test::Differences;
use Test::Deep;

require Test::NoWarnings;

use MediaWords::Crawler::Engine;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::MediaSets;
use MediaWords::DBI::Stories;
use MediaWords::Test::DB;
use MediaWords::Test::Data;
use MediaWords::Test::LocalServer;
use DBIx::Simple::MediaWords;
use MediaWords::StoryVectors;
use LWP::UserAgent;

use Data::Sorting qw( :basics :arrays :extras );
use Readonly;

# add a test media source and feed to the database
sub add_test_feed
{
    my ( $db, $url_to_crawl ) = @_;

    Readonly my $sw_data_start_date => '2008-02-03';
    Readonly my $sw_data_end_date   => '2014-02-27';

    my $test_medium = $db->query(
"insert into media (name, url, moderated, feeds_added, sw_data_start_date, sw_data_end_date) values (?, ?, ?, ?, ?, ?) returning *",
        '_ Crawler Test', $url_to_crawl, 0, 0, $sw_data_start_date, $sw_data_end_date
    )->hash;

    ok( MediaWords::StoryVectors::_medium_has_story_words_start_date( $test_medium ) );
    ok( MediaWords::StoryVectors::_medium_has_story_words_end_date( $test_medium ) );

    is( MediaWords::StoryVectors::_get_story_words_start_date_for_medium( $test_medium ), $sw_data_start_date );
    is( MediaWords::StoryVectors::_get_story_words_end_date_for_medium( $test_medium ),   $sw_data_end_date );

    my $feed = $db->query(
        "insert into feeds (media_id, name, url) values (?, ?, ?) returning *",
        $test_medium->{ media_id },
        '_ Crawler Test',
        "$url_to_crawl" . "gv/test.rss"
    )->hash;

    MediaWords::DBI::MediaSets::create_for_medium( $db, $test_medium );

    ok( $feed->{ feeds_id }, "test feed created" );

    return $feed;
}

#use_ok 'Catalyst::Test', 'MediaWords';

    MediaWords::Test::DB::test_on_test_database(
        sub {
	  use Encode;
            my ( $db ) = @_;

	  add_test_feed( $db, 'http://example.com' );

	  $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;
	  	  MediaWords::Util::Config->get_config->{ mediawords }->{ allow_unauthenticated_api_requests } = 'yes';

	  is( MediaWords::Util::Config->get_config->{ mediawords }->{ allow_unauthenticated_api_requests }, 'yes' );

	  ok( request( '/api/v2/media/list' )->is_success, 'Request should succeed' );
	  ok( request( '/api/v2/media/list' )->is_success, 'Request should succeed' );

	}
						);

done_testing();
