use strict;
use warnings;

use utf8;
use Test::More;
use Test::Differences;
use Test::Deep;

use Data::Dumper;

use MediaWords::Test::DB;
use MediaWords::Util::Bitly;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

sub test_merge_story_stats()
{
    # New stats had an error, old stats didn't
    {
        my $old_stats = { data => { bitly_id => { foo => 'bar ' }, }, };
        my $new_stats = { error => 'An error occurred while fetching new stats', };
        my $expected_stats = $old_stats;

        cmp_deeply( MediaWords::Util::Bitly::merge_story_stats( $old_stats, $new_stats ), $expected_stats );
    }

    # Old stats had an error, new stats didn't
    {
        my $old_stats = { error => 'An error occurred while fetching old stats', };
        my $new_stats = { data => { bitly_id => { foo => 'bar ' }, }, };
        my $expected_stats = $new_stats;

        cmp_deeply( MediaWords::Util::Bitly::merge_story_stats( $old_stats, $new_stats ), $expected_stats );
    }

    # Both old and new stats had an error
    {
        my $old_stats = { error => 'An error occurred while fetching old stats', };
        my $new_stats = { error => 'An error occurred while fetching new stats', };
        my $expected_stats = $new_stats;

        cmp_deeply( MediaWords::Util::Bitly::merge_story_stats( $old_stats, $new_stats ), $expected_stats );
    }

    # Merge stats for different days
    {
        my $old_stats_clicks = {
            link_clicks => [
                { dt => 1, clicks => 1 },    #
                { dt => 2, clicks => 2 },    #
                { dt => 3, clicks => 3 },    #
            ]
        };
        my $new_stats_clicks = {
            link_clicks => [
                { dt => 4, clicks => 4 },    #
                { dt => 5, clicks => 5 },    #
                { dt => 6, clicks => 6 },    #
            ]
        };
        my $old_stats      = { data => { bitly_id => { clicks => [ $old_stats_clicks ] } } };
        my $new_stats      = { data => { bitly_id => { clicks => [ $new_stats_clicks ] } } };
        my $expected_stats = { data => { bitly_id => { clicks => [ $old_stats_clicks, $new_stats_clicks ] } } };

        cmp_deeply( MediaWords::Util::Bitly::merge_story_stats( $old_stats, $new_stats ), $expected_stats );
    }
}

sub main()
{
    plan tests => 4;

    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_merge_story_stats();
}

main();
