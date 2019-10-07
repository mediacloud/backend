package MediaWords::Test::Univision;

use strict;
use warnings;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

#
# Test MediaWords::Crawler::Download::Feed::Univision feed
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

use Test::More;
use Test::Deep;

use MediaWords::DB;
use MediaWords::Crawler::Engine;
use MediaWords::Crawler::Download::Feed::Univision;
use MediaWords::Util::ParseJSON;
use MediaWords::Test::HashServer;
use MediaWords::Test::DB::Create;
use MediaWords::Util::Config::Crawler;

sub _test_api_request_signature()
{
    # Invalid input
    eval { MediaWords::Crawler::Download::Feed::Univision::_api_request_url_with_signature( undef, undef, undef ) };
    ok( $@, 'Empty input' );

    eval {
        MediaWords::Crawler::Download::Feed::Univision::_api_request_url_with_signature( 'ftp://', 'client_id',
            'secret_key' );
    };
    ok( $@, 'Invalid URL' );

    eval {
        MediaWords::Crawler::Download::Feed::Univision::_api_request_url_with_signature( 'http://www.test.com/?client_id=a',
            'client_id', 'secret_key' );
    };
    ok( $@, 'URL with client_id' );

    # Sanitization and query parameter sorting
    is(
        MediaWords::Crawler::Download::Feed::Univision::_api_request_url_with_signature(
            'http://www.test.com/', 'client_id', 'secret_key'
        ),
        MediaWords::Crawler::Download::Feed::Univision::_api_request_url_with_signature(
            'http://www.test.com', 'client_id', 'secret_key'
        ),
        'With and without ending slash'
    );

    is(
        MediaWords::Crawler::Download::Feed::Univision::_api_request_url_with_signature(
            'http://www.test.com/', 'client_id', 'secret_key'
        ),
        MediaWords::Crawler::Download::Feed::Univision::_api_request_url_with_signature(
            'http://www.test.com', 'client_id', 'secret_key'
        ),
        'With and without ending slash'
    );

    like(
        MediaWords::Crawler::Download::Feed::Univision::_api_request_url_with_signature(
            'http://www.test.com/?c=c&c=b&c=a&b=b&b=a&a=a',
            'client_id', 'secret_key'
        ),
        qr/a=a&b=a&b=b&c=a&c=b&c=c/,
        'Sorted query parameters'
    );
}

# Basic request
sub _test_api_request($$$)
{
    my ( $univision_url, $univision_client_id, $univision_client_secret ) = @_;

    my $api_request_url = MediaWords::Crawler::Download::Feed::Univision::_api_request_url_with_signature(
    	$univision_url,				#
    	$univision_client_id,		#
        $univision_client_secret,	#
    );
    ok( length( $api_request_url ) > 0, 'API request URL is not empty' );

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get( $api_request_url );
    ok( $response->is_success, 'API request was successful' );

    my $json_string = $response->decoded_content;
    ok( $json_string, 'JSON response is not empty' );

    my $json;
    eval { $json = MediaWords::Util::ParseJSON::decode_json( $json_string ) };
    ok( ( !$@ ), "JSON recoding of JSON succeeded: $json_string" );

    is( $json->{ 'status' }, 'success', "JSON response was successful: $json_string" );
    ok( $json->{ 'data' }, 'JSON response has "data" key' );
}

sub _test_fetch_handle_download($$$)
{
    my ( $db, $univision_url, $crawler_config ) = @_;

    my $medium = $db->create(
        'media',
        {
            name => "Media for test feed $univision_url",
            url  => 'http://www.univision.com/',
        }
    );

    my $feed = $db->create(
        'feeds',
        {
            name     => 'feed',
            type     => 'univision',
            url      => $univision_url,
            media_id => $medium->{ media_id }
        }
    );

    my $download = MediaWords::Test::DB::Create::create_download_for_feed( $db, $feed );

    my $handler = MediaWords::Crawler::Engine::handler_for_download( $db, $download );

    my $response = $handler->fetch_download( $db, $download, $crawler_config );
    $handler->handle_response( $db, $download, $response );

    $download = $db->find_by_id( 'downloads', $download->{ downloads_id } );
    is( $download->{ state }, 'success', "Download's state is not 'success': " . $download->{ state } );
    ok( !$download->{ error_message }, "Download's error_message should be empty: " . $download->{ error_message } );

    my $story_downloads = $db->query(
        <<EOF,
        SELECT *
        FROM downloads
        WHERE feeds_id = ?
          AND type = 'content'
          AND state = 'pending'
EOF
        $download->{ feeds_id }
    )->hashes;
    ok( scalar( @{ $story_downloads } ) > 0, 'One or more story downloads were derived from feed' );
}

sub test_univision($$$$)
{
    my ( $db, $univision_url, $univision_client_id, $univision_client_secret ) = @_;

    say STDERR "Testing against $univision_url with $univision_client_id:$univision_client_secret...";

    _test_api_request_signature();
    _test_api_request( $univision_url, $univision_client_id, $univision_client_secret );

    {
        package UnivisionTestCrawlerConfig;

        use strict;
        use warnings;

        use base 'MediaWords::Util::Config::Crawler';

        sub univision_client_id()
        {
            return $univision_client_id;
        }

        sub univision_client_secret()
        {
            return $univision_client_secret;
        }

        1;
    }

    my $crawler_config = UnivisionTestCrawlerConfig->new();

    _test_fetch_handle_download( $db, $univision_url, $crawler_config );
}

1;
