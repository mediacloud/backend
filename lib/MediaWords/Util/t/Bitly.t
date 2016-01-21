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

    # Both old and new stats had an error
    {
        my $old_stats = { error => 'An error occurred while fetching old stats', };
        my $new_stats = { error => 'An error occurred while fetching new stats', };
        my $expected_stats = $new_stats;

        cmp_deeply( MediaWords::Util::Bitly::merge_story_stats( $old_stats, $new_stats ), $expected_stats );
    }
}

sub main()
{
    plan tests => 2;

    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_merge_story_stats();
}

main();
