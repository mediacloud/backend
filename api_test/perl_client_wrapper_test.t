use strict;
use warnings;

#use Test::More;
use Test::More tests => 2;

# use MediaWords::Test::DB;
# use MediaWords::Test::Data;
# use MediaWords::Test::LocalServer;

#use Test::More skip_all => "disabling until auth changes are pushed";

use MediaWords::ApiClient;

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

    my $mc = new MediaWords::ApiClient::MediaCloud( $key );

    #say STDERR Dumper( $mc );
    ##say STDERR Dumper( \%{ $mc  } );
    $mc::V2_API_URL = "http://0:3000/api/v2/";

    say STDERR Dumper( $mc::V2_API_URL );

    #say STDERR $mc->V2_API_URL;
    #say STDERR $mc.V2_API_URL;

    #$mc.V2_API_URL = "http://0:3000/api/v2/";

    # foreach my $base_url ( @{ $urls } )
    {

        my $actual_response = $mc->mediaList();

        my $expected_response = [
            {
                'media_id'          => 1,
                'media_source_tags' => [
                    {
                        'tag_sets_id'     => 1,
                        'show_on_stories' => undef,
                        'tags_id'         => 17,
                        'description'     => undef,
                        'show_on_media'   => undef,
                        'tag_set'         => 'collection',
                        'tag'             => 'cc',
                        'label'           => undef
                    },
                    {
                        'tag_sets_id'     => 1,
                        'show_on_stories' => undef,
                        'tags_id'         => 18,
                        'description'     => undef,
                        'show_on_media'   => undef,
                        'tag_set'         => 'collection',
                        'tag'             => 'news',
                        'label'           => undef
                    }
                ],
                'name'       => 'Wikinews, the free news source',
                'url'        => 'http://en.wikinews.org/wiki/Main_Page',
                'media_sets' => [
                    {
                        'media_sets_id' => 1,
                        'name'          => 'CC_sources',
                        'description'   => 'Creative Commons Sources'
                    },
                    {
                        'media_sets_id' => 6,
                        'name'          => 'news',
                        'description'   => 'news'
                    }
                ]
            }
        ];

        #say STDERR Dumper( $actual_response );

        cmp_deeply( $actual_response, $expected_response, "response format mismatch for " );
    }

}

#test_stories_public();
#test_stories_non_public();
#test_tags();
test_media();
