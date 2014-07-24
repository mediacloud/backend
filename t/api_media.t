use strict;
use warnings;

#use Test::More;
use Test::More tests => 10;

# use MediaWords::Test::DB;
# use MediaWords::Test::Data;
# use MediaWords::Test::LocalServer;

#use Test::More skip_all => "disabling until auth changes are pushed";

BEGIN
{
    $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;
    use_ok 'Catalyst::Test', 'MediaWords';
}

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
    $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;
    use_ok 'Catalyst::Test', 'MediaWords';
}

use Test::Differences;
use Test::Deep;

require Test::NoWarnings;

use Data::Dumper;

use MediaWords::Crawler::Engine;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::MediaSets;
use MediaWords::DBI::Stories;
use MediaWords::Test::DB;
use MediaWords::Test::Data;
use MediaWords::Test::LocalServer;
use DBIx::Simple::MediaWords;
use MediaWords::StoryVectors;
use LWP::UserAgent;
use JSON;

use Data::Sorting qw( :basics :arrays :extras );
use Readonly;

$ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;

sub test_media
{
    use Encode;
    my ( $db ) = @_;

    my $key = 'f66a50230d54afaf18822808aed649f1d6ca72b08fb06d5efb6247afe9fbae52';

    my $urls = [ '/api/v2/media/single/1', '/api/v2/media/list/?rows=1' ];

    #my $urls = [ '/api/v2/media/list/?rows=1' ];

    foreach my $base_url ( @{ $urls } )
    {

        my $url;
        if ( index( $base_url, "?" ) != -1 )
        {
            $url = "$base_url&key=$key";
        }
        else
        {
            $url = "$base_url?key=$key";
        }

        my $response = request( "$url" );

        #say STDERR Dumper( $response );
        #say STDERR Dumper( $response->base );

        ok( $response->is_success, 'Request should succeed' );

        my $resp_object = decode_json( $response->decoded_content() );

        #say STDERR Dumper( $resp_object );

        my $expected_response = [
            {
                'media_id'          => 1,
                'media_source_tags' => [
                    {
                        'tag_sets_id'     => 1,
                        'show_on_stories' => undef,
                        'tags_id'         => 1,
                        'description'     => undef,
                        'show_on_media'   => undef,
                        'tag_set'         => 'collection',
                        'tag'             => 'news collection:cc',
                        'label'           => undef
                    }
                ],
                'name'       => 'Wikinews, the free news source',
                'url'        => 'http://en.wikinews.org/wiki/Main_Page',
                'media_sets' => []
            }
        ];

        cmp_deeply( $resp_object, $expected_response, "response format mismatch for $url" );

        foreach my $medium ( @{ $expected_response } )
        {
            my $media_id = $medium->{ media_id };

            $response = request( "/api/v2/feeds/list?key=$key&media_id=$media_id" );
            ok( $response->is_success, 'Request should succeed' );

            if ( !$response->is_success )
            {
                say STDERR Dumper( $response->decoded_content() );
            }

            my $expected_feed = [
                {
                    'media_id'  => 1,
                    'feed_type' => 'syndicated',
                    'name'      => 'English Wikinews Atom feed.',
                    'url' =>
'http://en.wikinews.org/w/index.php?title=Special:NewsFeed&feed=atom&categories=Published&notcategories=No%20publish%7CArchived%7CAutoArchived%7Cdisputed&namespace=0&count=30&hourcount=124&ordermethod=categoryadd&stablepages=only',
                    'feeds_id' => 1
                }
            ];

            my $feed_resp_object = decode_json( $response->decoded_content() );

            #say STDERR Dumper( $feed_resp_object );

            cmp_deeply( $feed_resp_object, $expected_feed, 'response format mismatch for feed' );
        }
    }

}

test_media();
done_testing();
