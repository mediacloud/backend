use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::Test::API;
use MediaWords::Test::Rows;
use MediaWords::Test::DB::Create;

use MediaWords::DBI::Downloads::Store;

# test downloads/list and single
sub test_downloads($)
{
    my ( $db ) = @_;

    MediaWords::Test::API::setup_test_api_key( $db );

    my $label = "downloads/list";

    my $medium = MediaWords::Test::DB::Create::create_test_medium( $db, $label );
    my $feed = MediaWords::Test::DB::Create::create_test_feed( $db, $label, $medium );
    for my $i ( 1 .. 10 )
    {
        my $download = $db->create(
            'downloads',
            {
                feeds_id => $feed->{ feeds_id },
                url      => 'http://test.download/' . $i,
                host     => 'test.download',
                type     => 'feed',
                state    => 'success',
                path     => $i + $i,
                priority => $i,
                sequence => $i * $i
            }
        );

        my $content = "content $download->{ downloads_id }";
        MediaWords::DBI::Downloads::Store::store_content( $db, $download, $content );
    }

    my $expected_downloads = $db->query( "select * from downloads where feeds_id = ?", $feed->{ feeds_id } )->hashes;
    map { $_->{ raw_content } = "content $_->{ downloads_id }" } @{ $expected_downloads };

    my $got_downloads = MediaWords::Test::API::test_get( '/api/v2/downloads/list', { feeds_id => $feed->{ feeds_id } } );

    my $fields = [ qw/feeds_id url type state priority sequence download_time host/ ];
    MediaWords::Test::Rows::rows_match( $label, $got_downloads, $expected_downloads, "downloads_id", $fields );

    $label = "downloads/single";

    my $expected_single = $expected_downloads->[ 0 ];

    my $got_download = MediaWords::Test::API::test_get( '/api/v2/downloads/single/' . $expected_single->{ downloads_id }, {} );
    MediaWords::Test::Rows::rows_match( $label, $got_download, [ $expected_single ], 'downloads_id', $fields );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_downloads( $db );

    done_testing();
}

main();
