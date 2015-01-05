use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 10;

use Data::Dumper;

use MediaWords::Test::DB;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::Facebook' );
}

my $_last_request_time;

sub test_share_count($)
{
    my ( $db ) = @_;

    my $google_count = MediaWords::Util::Facebook::get_url_share_count( $db, 'http://google.com' );

    my $nyt_ferguson_count = MediaWords::Util::Facebook::get_url_share_count( $db,
        'http://www.nytimes.com/interactive/2014/08/13/us/ferguson-missouri-town-under-siege-after-police-shooting.html' );

    my $zero_count = MediaWords::Util::Facebook::get_url_share_count( $db, 'http://totally.bogus.url.123456' );

    ok( $google_count > 10090300,    "google count '$google_count' should be greater than 10090300" );
    ok( $nyt_ferguson_count > 25000, "nyt ferguson count '$nyt_ferguson_count' should be greater than 25,000" );
    ok( $zero_count == 0,            "zero count '$zero_count' should be 0" );
}

sub test_store_result($)
{
    my ( $db ) = @_;
    
    my $media = MediaWords::Test::DB::create_test_story_stack( $db, { A => { B => [ 1, 2, 3 ] } } );
    
    my $story = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 1 };
    
    $story->{ url } = 'http://google.com';
    
    my $count = MediaWords::Util::Facebook::get_and_store_share_count( $db, $story );
    
    my $ss = $db->query( 'select * from story_statistics where stories_id = ?', $story->{ stories_id } )->hash;
    
    ok( $ss, 'story_statistics row exists after initial insert' );
    
    is( $ss->{ facebook_share_count }, $count, "stored url share count" );
    ok( !defined( $ss->{ facebook_share_count_error } ), "null url share count error" );
    
    $story->{ url } = 'foobar';
    
    MediaWords::Util::Facebook::get_and_store_share_count( $db, $story );
    
    my $sse = $db->query( 'select * from story_statistics where stories_id = ?', $story->{ stories_id } )->hash;
    
    is( $sse->{ facebook_share_count }, 0, "stored url share count should 0 after error" );
    ok( defined( $sse->{ facebook_share_count_error } ), "stored url share count should contain error" );
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

            test_share_count( $db );
            test_store_result( $db );
        }
    );
}

main();
