use strict;
use warnings;

# test TM::Mine::_import_month_within_respider_date

use English '-no_match_vars';

use Test::More;

use MediaWords::TM::Mine;

sub test_import_month_within_respider_date()
{
    my $topic = {
        start_date => '2019-01-01',
        end_date => '2019-06-01',
        respider_stories => 'f',
        respider_start_date => undef,
        respider_end_date => undef
    };

    # if none of the respider setting are correct, we should always return true
    ok( MediaWords::TM::Mine::_import_month_within_respider_date( $topic, 0 ) );
    ok( MediaWords::TM::Mine::_import_month_within_respider_date( $topic, 1 ) );
    ok( MediaWords::TM::Mine::_import_month_within_respider_date( $topic, 100 ) );

    # if respider_stories is true but neither respider date is set, always return true
    $topic->{ respider_stories } = 1;
    ok( MediaWords::TM::Mine::_import_month_within_respider_date( $topic, 0 ) );
    ok( MediaWords::TM::Mine::_import_month_within_respider_date( $topic, 1 ) );
    ok( MediaWords::TM::Mine::_import_month_within_respider_date( $topic, 100 ) );

    # should only import the dates after the respider end date
    $topic->{ respider_end_date } = '2019-05-01';
    ok( !MediaWords::TM::Mine::_import_month_within_respider_date( $topic,  0 ) );
    ok( !MediaWords::TM::Mine::_import_month_within_respider_date( $topic, 3 ) );
    ok( MediaWords::TM::Mine::_import_month_within_respider_date( $topic, 4 ) );

    # make sure we capture the whole previous month if the end date is within a month
    $topic->{ respider_end_date } = '2019-04-02';
    ok( MediaWords::TM::Mine::_import_month_within_respider_date( $topic,  3 ) );

    # should only import the dates before the repsider start date
    $topic->{ respider_start_date } = '2019-02-01';
    ok( MediaWords::TM::Mine::_import_month_within_respider_date( $topic,  0 ) );
    ok( !MediaWords::TM::Mine::_import_month_within_respider_date( $topic,  1 ) );
}

sub main
{
    test_import_month_within_respider_date();

    done_testing();
}

main();
