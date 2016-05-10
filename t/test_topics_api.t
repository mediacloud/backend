#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin";
    use lib "$FindBin::Bin/../lib";
    use Catalyst::Test 'MediaWords';
}

use JSON;

use List::MoreUtils "uniq";
use List::Util "shuffle";

use Math::Prime::Util;

use Modern::Perl "2015";

use MediaWords;

use MediaWords::CM::Dump;

use MediaWords::CommonLibs;

use MediaWords::Pg::Schema;

use MediaWords::Test::DB;

use MediaWords::Util::Web;

use MediaWords::Controller::Api::V2::Topics::Stories;

use Readonly;

use Test::More;

my $TEST_API_KEY;

Readonly my $TEST_HTTP_SERVER_PORT => '3000';

Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

# This should match the DEFAULT_STORY_LIMIT in Stories.pm
Readonly my $DEFAULT_STORY_LIMIT => 10;

# A constant used to generate consistent orderings in test sorts
Readonly my $TEST_MODULO => 6;

sub add_controversy_link
{
    my ( $db, $controversy, $story, $ref_story ) = @_;

    $db->create(
        'controversy_links',
        {
            controversies_id => $controversy->{ controversies_id },
            stories_id       => $story,
            url              => 'http://foo',
            redirect_url     => 'http://foo',
            ref_stories_id   => $ref_story,
        }
    );

}

sub add_bitly_count
{
    my ( $db, $id, $story, $click_count ) = @_;
    $db->query( "insert into bitly_clicks_total values ( \$1,\$2,\$3 )", $id, $story->{ stories_id }, $click_count );
}

sub add_controversy_story
{
    my ( $db, $controversy, $story ) = @_;

    $db->create( 'controversy_stories',
        { stories_id => $story->{ stories_id }, controversies_id => $controversy->{ controversies_id } } );
}

sub _api_request_url($;$)
{
    my ( $path, $params ) = @_;

    my $uri = URI->new( $path );

    $uri->query_param( 'key' => $TEST_API_KEY );

    if ( $params )
    {
        foreach my $key ( keys %{ $params } )
        {
            $uri->query_param( $key => $params->{ $key } );
        }
    }

    return $uri->as_string;
}

sub create_stories
{
    my ( $db, $stories, $controversies ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, $stories );

}

sub create_test_data
{

    my ( $test_db, $controversy_media_sources ) = @_;

    my $NUM_LINKS_PER_PAGE = 10;

    srand( 3 );

    # populate controversies table
    my $controversy = $test_db->create(
        'controversies',
        {
            name                => 'foo',
            solr_seed_query     => '',
            solr_seed_query_run => 'f',
            pattern             => '',
            description         => 'test controversy'
        }
    );

    my $controversy_dates = $test_db->create(
        'controversy_dates',
        {
            controversies_id => $controversy->{ controversies_id },
            start_date       => '2014-04-01',
            end_date         => '2014-06-01'
        }
    );

    # populate controversies_stories table
    # only include stories with id not multiples of $TEST_MODULO
    my $all_stories         = {};
    my $controversy_stories = [];

    for my $m ( values( %{ $controversy_media_sources } ) )
    {
        for my $f ( values( %{ $m->{ feeds } } ) )
        {
            while ( my ( $num, $story ) = each( %{ $f->{ stories } } ) )
            {
                if ( $num % $TEST_MODULO )
                {
                    my $cs = add_controversy_story( $test_db, $controversy, $story );
                    push @{ $controversy_stories }, $story->{ stories_id };
                }
                $all_stories->{ int( $num ) } = $story->{ stories_id };

                # modding by a different number than stories included in controversies
                # so that we will have bitly counts of 0

                add_bitly_count( $test_db, $num, $story, $num % ( $TEST_MODULO - 1 ) );
            }
        }
    }

    # populate controversies_links table
    while ( my ( $num, $story_id ) = each %{ $all_stories } )
    {
        my @factors = Math::Prime::Util::factor( $num );
        foreach my $factor ( uniq @factors )
        {
            if ( $factor != $num )
            {
                add_controversy_link( $test_db, $controversy, $all_stories->{ $factor }, $story_id );
            }
        }
    }

    MediaWords::CM::Dump::dump_controversy( $test_db, $controversy->{ controversies_id } );

}

sub _get_test_response
{

    my $base_url = shift;

    my $url = _api_request_url( $base_url->{ path }, $base_url->{ params } );

    my $response = request( $url );

}

sub test_media_list
{
    my $data = shift;

    my $base_url = { path => '/api/v2/topics/1/media/list' };

    my $response = _get_test_response( $base_url );

    Test::More::ok( $response->is_success, 'Request should succeed' );

    my $actual_response = JSON::decode_json( $response->decoded_content() );

    ok( scalar @{ $actual_response->{ media } } == 3,
        "returned unexpected number of media scalar $actual_response->{ media }" );

    # Check descending link count
    foreach my $m ( 1 .. $#{ $actual_response->{ media } } )
    {
        ok( $actual_response->{ media }[ $m ]->{ inlink_count } <= $actual_response->{ media }[ $m - 1 ]->{ inlink_count } );
    }

    # Check that we have right number of inlink counts for each media source

    my $controversy_stories = _get_story_link_counts( $data );

    my $inlink_counts = { F => 4, D => 2, A => 0 };

    foreach my $mediasource ( @{ $actual_response->{ media } } )
    {
        ok( $mediasource->{ inlink_count } == $inlink_counts->{ $mediasource->{ name } } );
    }
}

sub test_story_count
{

    # The number of stories returned in stories/list matches the count in cdts

    my $base_url = { path => '/api/v2/topics/1/stories/list' };

    my $response = _get_test_response( $base_url );

    Test::More::ok( $response->is_success, 'Request should succeed' );

    my $actual_response = JSON::decode_json( $response->decoded_content() );

    Test::More::ok( scalar @{ $actual_response->{ stories } } == $DEFAULT_STORY_LIMIT );

}

sub _get_story_link_counts
{
    my $data = shift;

    # umber of prime factors outside the media source
    my $counts = {
        1  => 0,
        2  => 0,
        3  => 0,
        4  => 0,
        5  => 0,
        7  => 0,
        8  => 1,
        9  => 1,
        10 => 2,
        11 => 0,
        13 => 0,
        14 => 2,
        15 => 0
    };

    my %return_counts = map { "story " . $_ => $counts->{ $_ } } keys %{ $counts };
    return \%return_counts;

}

sub _get_expected_bitly_link_counts
{
    my $return_counts = {};

    foreach my $m ( 1 .. 15 )
    {

        if ( $m % $TEST_MODULO )
        {

            $return_counts->{ "story " . $m } = $m % ( $TEST_MODULO - 1 );
        }

    }
    return $return_counts;

}

sub test_default_sort
{

    my $data = shift;

    my $base_url = { path => '/api/v2/topics/1/stories/list?limit=20' };

    my $sort_key = "inlink_count";

    my $expected_counts = _get_story_link_counts( $data );

    _test_sort( $data, $expected_counts, $base_url, $sort_key );

}

sub test_social_sort
{

    my $data = shift;

    my $base_url = { path => '/api/v2/topics/1/stories/list?sort=social&limit=20' };

    my $sort_key = "bitly_click_count";

    my $expected_counts = _get_expected_bitly_link_counts();

    _test_sort( $data, $expected_counts, $base_url, $sort_key );

}

sub _test_sort
{

    # Make sure that only expected stories are in stories list response
    # in the appropriate order

    my ( $data, $expected_counts, $base_url, $sort_key ) = @_;

    my $response = _get_test_response( $base_url );

    my $actual_response = JSON::decode_json( $response->decoded_content() );

    my $actual_stories_inlink_counts = {};
    my $actual_stories_order         = ();

    foreach my $story ( @{ $actual_response->{ stories } } )
    {
        $actual_stories_inlink_counts->{ $story->{ 'title' } } = $story->{ $sort_key };
        my @story_info = ( $story->{ $sort_key }, $story->{ 'stories_id' } );
        push @{ $actual_stories_order }, \@story_info;
    }

    is_deeply( $actual_stories_inlink_counts, $expected_counts, 'expected stories' );

    foreach my $story ( 1 .. scalar @{ $actual_stories_order } - 1 )
    {
        ok( $actual_stories_order->[ $story ]->[ 0 ] <= $actual_stories_order->[ $story - 1 ]->[ 0 ] );
        if ( $actual_stories_order->[ $story ]->[ 0 ] == $actual_stories_order->[ $story - 1 ]->[ 0 ] )
        {
            ok( $actual_stories_order->[ $story ]->[ 1 ] > $actual_stories_order->[ $story - 1 ]->[ 1 ] );
        }
    }
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {

            my $db = shift;

            my $stories = {
                A => {
                    B => [ 1, 2, 3 ],
                    C => [ 4, 5, 6, 15 ]
                },
                D => { E => [ 7, 8, 9 ] },
                F => {
                    G => [ 10, ],
                    H => [ 11, 12, 13, 14, ]
                }
            };

            my $controversy_media = create_stories( $db, $stories );

            create_test_data( $db, $controversy_media );
            $TEST_API_KEY = MediaWords::Test::DB::create_test_user( $db );
            test_story_count();
            test_default_sort( $stories );
            test_social_sort( $stories );
            test_media_list( $stories );
            done_testing();
        }
    );
}

main();
