use strict;
use warnings;

use utf8;
use Test::More;

use Data::Dumper;

use MediaWords::Test::DB;
use MediaWords::Util::Facebook;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

my $_last_request_time;

sub test_share_comment_counts($)
{
    my ( $db ) = @_;

    my ( $google_share_count, $google_comment_count ) =
      MediaWords::Util::Facebook::get_url_share_comment_counts( $db, 'http://google.com' );
    ok( $google_share_count > 10090300, "google share count '$google_share_count' should be greater than 10,090,300" );
    ok( $google_comment_count > 10000,  "google comment count '$google_comment_count' should be greater than 10,000" );

    my ( $nyt_ferguson_share_count, $nyt_ferguson_comment_count ) =
      MediaWords::Util::Facebook::get_url_share_comment_counts( $db,
        'http://www.nytimes.com/interactive/2014/08/13/us/ferguson-missouri-town-under-siege-after-police-shooting.html' );
    ok( $nyt_ferguson_share_count > 25000, "nyt ferguson count '$nyt_ferguson_share_count' should be greater than 25,000" );

    my ( $zero_share_count, $zero_comment_count ) =
      MediaWords::Util::Facebook::get_url_share_comment_counts( $db, 'http://totally.bogus.url.123456' );
    ok( $zero_share_count == 0,   "zero share count '$zero_share_count' should be 0" );
    ok( $zero_comment_count == 0, "zero comment count '$zero_comment_count' should be 0" );
}

sub test_store_result($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, { A => { B => [ 1, 2, 3 ] } } );

    my $story = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 1 };

    $story->{ url } = 'http://google.com';

    my ( $share_count, $comment_count ) = MediaWords::Util::Facebook::get_and_store_share_comment_counts( $db, $story );

    my $ss = $db->query( 'select * from story_statistics where stories_id = ?', $story->{ stories_id } )->hash;

    ok( $ss, 'story_statistics row exists after initial insert' );

    is( $ss->{ facebook_share_count },   $share_count,   "stored url share count" );
    is( $ss->{ facebook_comment_count }, $comment_count, "stored url comment count" );
    ok( !defined( $ss->{ facebook_api_error } ), "null url share count error" );

    $story->{ url } = 'foobar';

    MediaWords::Util::Facebook::get_and_store_share_comment_counts( $db, $story );

    my $sse = $db->query( 'select * from story_statistics where stories_id = ?', $story->{ stories_id } )->hash;

    is( $sse->{ facebook_share_count },   0, "stored url share count should 0 after error" );
    is( $sse->{ facebook_comment_count }, 0, "stored url comment count should 0 after error" );
    ok( defined( $sse->{ facebook_api_error } ), "facebook should have reported an error" );
}

sub main()
{
    my $config = MediaWords::Util::Config::get_config;
    unless ($config->{ facebook }->{ enabled } eq 'yes'
        and $config->{ facebook }->{ app_id }
        and $config->{ facebook }->{ app_secret } )
    {
        # Facebook's API is not enabled, but maybe there are environment
        # variables set by the automated testing environment
        if ( defined $ENV{ 'FACEBOOK_APP_ID' } and defined $ENV{ 'FACEBOOK_APP_SECRET' } )
        {
            $config->{ facebook }->{ enabled }    = 'yes';
            $config->{ facebook }->{ app_id }     = $ENV{ 'FACEBOOK_APP_ID' };
            $config->{ facebook }->{ app_secret } = $ENV{ 'FACEBOOK_APP_SECRET' };

            # FIXME Awful trick to modify config's cache
            $MediaWords::Util::Config::_config = $config;
        }
        else
        {
            plan skip_all => "Facebook's API is not enabled.";
            return;
        }
    }

    plan tests => 12;

    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_share_comment_counts( $db );
            test_store_result( $db );
        }
    );
}

main();
