use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::DB;
use MediaWords::Test::API;
use MediaWords::Test::Rows;
use MediaWords::Test::DB::Create;

# test mediahealth/list and single
sub test_mediahealth($)
{
    my ( $db ) = @_;

    MediaWords::Test::API::setup_test_api_key( $db );

    my $label = "mediahealth/list";

    my $metrics = [
        qw/num_stories num_stories_w num_stories_90 num_stories_y num_sentences num_sentences_w/,
        qw/num_sentences_90 num_sentences_y expected_stories expected_sentences coverage_gaps/
    ];
    for my $i ( 1 .. 10 )
    {
        my $medium = MediaWords::Test::DB::Create::create_test_medium( $db, "$label $i" );
        my $mh = {
            media_id        => $medium->{ media_id },
            is_healthy      => ( $medium->{ media_id } % 2 ) ? 't' : 'f',
            has_active_feed => ( $medium->{ media_id } % 2 ) ? 't' : 'f',
            start_date      => '2011-01-01',
            end_date        => '2017-01-01'
        };

        map { $mh->{ $_ } = $i * length( $_ ) } @{ $metrics };

        $db->create( 'media_health', $mh );
    }

    my $expected_mhs = $db->query( <<SQL,
        SELECT mh.*
        FROM media_health AS mh
            INNER JOIN media AS m USING (media_id)
        WHERE m.name LIKE ? || '%'
SQL
        $label
    )->hashes;

    my $media_id_params = join( '&', map { "media_id=$_->{ media_id }" } @{ $expected_mhs } );

    my $got_mhs = MediaWords::Test::API::test_get( '/api/v2/mediahealth/list?' . $media_id_params, {} );

    my $fields = [ qw/media_id is_healthy has_active_feed start_date end_date/, @{ $metrics } ];
    MediaWords::Test::Rows::rows_match( $label, $got_mhs, $expected_mhs, 'media_id', $fields );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_mediahealth( $db );

    done_testing();
}

main();
