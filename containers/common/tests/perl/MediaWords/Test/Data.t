use strict;
use warnings;

use Test::More;
use Test::Deep;

use Data::Dumper;
use DateTime;

use MediaWords::Test::Data;

sub test_adjust_test_timezone()
{
    my $test_timezone = 'America/New_York';
    my $test_datetime = DateTime->new(
        year      => 2009,
        month     => 6,
        day       => 8,
        hour      => 1,
        minute    => 57,
        second    => 42,
        time_zone => $test_timezone,
    );
    my $test_publish_date = $test_datetime->strftime( '%F %T' );    # 2009-06-08 01:57:42
    my $test_stories      = [
        {
            'stories_id'   => 1,
            'publish_date' => $test_publish_date,
        },
        {
            'stories_id' => 2,

            # No "publish_date"
        }
    ];

    my $expected_datetime = $test_datetime->clone();
    $expected_datetime->set_time_zone( 'local' );
    my $expected_publish_date = $expected_datetime->strftime( '%F %T' );
    my $expected_test_stories = [
        {
            'stories_id'   => 1,
            'publish_date' => $expected_publish_date,
        },
        {
            'stories_id' => 2,

            # No "publish_date"
        }
    ];

    my $actual_test_stories = MediaWords::Test::Data::adjust_test_timezone( $test_stories, $test_timezone );

    cmp_deeply( $actual_test_stories, $expected_test_stories );
}

sub main()
{
    plan tests => 1;

    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_adjust_test_timezone();
}

main();
