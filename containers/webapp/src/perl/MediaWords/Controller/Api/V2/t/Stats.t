use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::Test::API;

use MediaWords::DBI::Stats;

# test downloads/list and single
sub test_stats($)
{
    my ( $db ) = @_;

    MediaWords::Test::API::setup_test_api_key( $db );

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

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_stats( $db );

    done_testing();
}

main();
