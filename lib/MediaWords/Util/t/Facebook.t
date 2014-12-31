use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 5;

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
        }
    );
}

main();
