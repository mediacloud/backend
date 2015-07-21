use strict;
use warnings;

#use Test::More;
use Test::More tests => 20;

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

        my $actual_response = decode_json( $response->decoded_content() );

        #say STDERR Dumper( $actual_response );

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

        cmp_deeply( $actual_response, $expected_response, "response format mismatch for $url" );

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

            my $feed_actual_response = decode_json( $response->decoded_content() );

            #say STDERR Dumper( $feed_actual_response );

            cmp_deeply( $feed_actual_response, $expected_feed, 'response format mismatch for feed' );
        }
    }

}

sub test_tags
{
    use Encode;
    my ( $db ) = @_;

    my $key = 'f66a50230d54afaf18822808aed649f1d6ca72b08fb06d5efb6247afe9fbae52';

    my $urls =
      [ '/api/v2/tags/single/4', '/api/v2/tags/list/?last_tags_id=3&rows=1', '/api/v2/tags/list?search=independent', ];

    foreach my $base_url ( @{ $urls } )
    {

        my $url = ( index( $base_url, "?" ) != -1 ) ? "$base_url&key=$key" : "$base_url?key=$key";

        my $response = request( "$url" );

        ok( $response->is_success, 'Request should succeed' );

        my $actual_response = decode_json( $response->decoded_content() );

        my $expected_response = [
            {
                "tag_sets_id"     => 2,
                "show_on_stories" => undef,
                "label"           => "Independent Group",
                "tag"             => "Independent Group",
                "tags_id"         => 4,
                "show_on_media"   => undef,
                "tag_set_name"    => 'media_type',
                "tag_set_label"   => 'Media Type',
                "tag_set_description" =>
                  'High level topology for media sources for use across a variety of different topics',
                "description" =>
"An academic or nonprofit group that is not affiliated with the private sector or government, such as the Electronic Frontier Foundation or the Center for Democracy and Technology)"
            }
        ];

        cmp_deeply( $actual_response, $expected_response, "response format mismatch for $url" );
    }
}

sub test_stories_public
{
    use Encode;
    my ( $db ) = @_;

    my $key = 'f66a50230d54afaf18822808aed649f1d6ca72b08fb06d5efb6247afe9fbae52';

    my $base_url = '/api/v2/stories_public/list/';

    my $url;
    if ( index( $base_url, "?" ) != -1 )
    {
        $url = "$base_url&key=$key";
    }
    else
    {
        $url = "$base_url?key=$key";
    }

    $url .= "&q=sentence:obama&rows=2&sentences=1&text=1";

    say STDERR $url;

    my $response = request( "$url" );

    ok( $response->is_success, 'Request should succeed' );

    if ( !$response->is_success )
    {
        say STDERR $response->decoded_content();
    }

    my $actual_response = decode_json( $response->decoded_content() );

    #say STDERR Dumper( $actual_response );

    my $expected_response = [
        {
            'collect_date'         => '2014-06-02 17:33:04',
            'story_tags'           => [],
            'media_name'           => 'Boing Boing',
            'media_id'             => 2,
            'publish_date'         => '2014-06-02 01:00:59',
            'processed_stories_id' => '67',
            'stories_id'           => 67,
            'url'                  => 'http://boingboing.net/2014/06/01/this-day-in-blogging-history-228.html',
            'guid'                 => 'http://boingboing.net/2014/06/01/this-day-in-blogging-history-228.html',
            'media_url'            => 'http://boingboing.net/',
            'language'             => 'en',
            'title' =>
'This Day in Blogging History: Turkish Spring in Gezi; Obama supports torture-evidence suppression law; Quaker football&#160;cheer',
        }
    ];

    cmp_deeply( $actual_response, $expected_response );
}

sub test_stories_non_public
{
    use Encode;
    my ( $db ) = @_;

    my $key = 'f66a50230d54afaf18822808aed649f1d6ca72b08fb06d5efb6247afe9fbae52';

    my $base_url = '/api/v2/stories/list/';

    my $url;
    if ( index( $base_url, "?" ) != -1 )
    {
        $url = "$base_url&key=$key";
    }
    else
    {
        $url = "$base_url?key=$key";
    }

    $url .= "&q=sentence:obama&rows=2&sentences=1&text=1";

    say STDERR $url;

    my $response = request( "$url" );

    ok( $response->is_success, 'Request should succeed' );

    if ( !$response->is_success )
    {
        say STDERR $response->decoded_content();
    }

    my $actual_response = decode_json( $response->decoded_content() );

    #say STDERR Dumper( $actual_response );

    my $expected_response = [
        {
            'story_text' => " 

 This Day in Blogging History: Turkish Spring in Gezi; Obama supports torture-evidence suppression law; Quaker football\x{a0}cheer 



     

 \x{2014} FEATURED \x{2014}

  

 \x{2014} COMICS \x{2014}

 

 \x{2014} RECENTLY \x{2014}

            

 \x{2014} FOLLOW US \x{2014}   

  Find us on  Twitter ,  Google+ ,  IRC , and  Facebook . Subscribe to our  RSS feed  or  daily email . 

             

 \x{2014} POLICIES  \x{2014}             

  Please read our  Terms of Service ,  Privacy Policy , and  Community Guidelines . Except where indicated, Boing Boing is licensed under a Creative\x{a0}Commons License permitting  non-commercial sharing with attribution  

  Turkish Spring: Taksim Gezi Park protests in Istanbul:  Taksim Gezi Park in Istanbul is alive with protest at this moment. The action began on May 28, when environmentalists protested plans to remove the park and replace it with a mall, and were met with a brutal police crackdown. 

  Obama Supports New Law to Suppress Detainee Torture Photos:  The White House is actively supporting a new bill jointly sponsored by Sens. Lindsey Graham and Joe Lieberman -- called The Detainee Photographic Records Protection Act of 2009 -- that literally has no purpose other than to allow the government to suppress any \"photograph taken between September 11, 2001 and January 22, 2009 relating to the treatment of individuals engaged, captured, or detained after September 11, 2001, by the Armed Forces of the United States in operations outside of the United States.\"

 Knock 'em down, beat 'em senseless, Do it till we reach consensus! 

",
            'is_fully_extracted'   => 1,
            'publish_date'         => '2014-06-02 01:00:59',
            'processed_stories_id' => '67',
            'url'                  => 'http://boingboing.net/2014/06/01/this-day-in-blogging-history-228.html',
            'db_row_last_updated'  => '2014-06-02 13:43:15.182044-04',
            'guid'                 => 'http://boingboing.net/2014/06/01/this-day-in-blogging-history-228.html',
            'media_url'            => 'http://boingboing.net/',
            'collect_date'         => '2014-06-02 17:33:04',
            'language'             => 'en',
            'full_text_rss'        => 0,
            'story_tags'           => [],

            #     'description'          => '<p>

            # <b>One year ago today</b>

# <a href="http://boingboing.net/2013/06/01/turkish-spring-taksim-gezi-pa.html">Turkish Spring: Taksim Gezi Park protests in Istanbul:</a> Taksim Gezi Park in Istanbul is alive with protest at this moment.</p>',
            'media_id'        => 2,
            'media_name'      => 'Boing Boing',
            'story_sentences' => [
                {
                    'sentence' =>
'This Day in Blogging History: Turkish Spring in Gezi; Obama supports torture-evidence suppression law; Quaker football cheer',
                    'sentence_number'     => 0,
                    'language'            => 'en',
                    'tags'                => [],
                    'media_id'            => 2,
                    'publish_date'        => '2014-06-02 01:00:59',
                    'stories_id'          => '67',
                    'db_row_last_updated' => '2014-06-02 13:43:15.182044-04',
                    'story_sentences_id'  => '998'
                },
                {
                    'sentence' =>
'Turkish Spring: Taksim Gezi Park protests in Istanbul: Taksim Gezi Park in Istanbul is alive with protest at this moment.',
                    'sentence_number'     => 1,
                    'language'            => 'en',
                    'tags'                => [],
                    'media_id'            => 2,
                    'publish_date'        => '2014-06-02 01:00:59',
                    'stories_id'          => '67',
                    'db_row_last_updated' => '2014-06-02 13:43:15.182044-04',
                    'story_sentences_id'  => '999'
                },
                {
                    'sentence' =>
'The action began on May 28, when environmentalists protested plans to remove the park and replace it with a mall, and were met with a brutal police crackdown.',
                    'sentence_number'     => 2,
                    'language'            => 'en',
                    'tags'                => [],
                    'media_id'            => 2,
                    'publish_date'        => '2014-06-02 01:00:59',
                    'stories_id'          => '67',
                    'db_row_last_updated' => '2014-06-02 13:43:15.182044-04',
                    'story_sentences_id'  => '1000'
                },
                {
                    'sentence' =>
'Obama Supports New Law to Suppress Detainee Torture Photos: The White House is actively supporting a new bill jointly sponsored by Sens. Lindsey Graham and Joe Lieberman -- called The Detainee Photographic Records Protection Act of 2009 -- that literally has no purpose other than to allow the government to suppress any "photograph taken between September 11, 2001 and January 22, 2009 relating to the treatment of individuals engaged, captured, or detained after September 11, 2001, by the Armed Forces of the United States in operations outside of the United States."',
                    'sentence_number'     => 3,
                    'language'            => 'en',
                    'tags'                => [],
                    'media_id'            => 2,
                    'publish_date'        => '2014-06-02 01:00:59',
                    'stories_id'          => '67',
                    'db_row_last_updated' => '2014-06-02 13:43:15.182044-04',
                    'story_sentences_id'  => '1001'
                },
                {
                    'sentence'            => 'Knock \'em down, beat \'em senseless, Do it till we reach consensus!',
                    'sentence_number'     => 4,
                    'language'            => 'en',
                    'tags'                => [],
                    'media_id'            => 2,
                    'publish_date'        => '2014-06-02 01:00:59',
                    'stories_id'          => '67',
                    'db_row_last_updated' => '2014-06-02 13:43:15.182044-04',
                    'story_sentences_id'  => '1002'
                }
            ],
            'stories_id' => '67',
            'title' =>
'This Day in Blogging History: Turkish Spring in Gezi; Obama supports torture-evidence suppression law; Quaker football&#160;cheer'
        }
    ];

    # say STDERR "Expected response: " . Dumper( $expected_response );
    # say STDERR "Actual response: " . Dumper( $actual_response );

    # Remove volatile values
    for my $response ( $expected_response, $actual_response )
    {
        for my $row ( @{ $response } )
        {
            delete $row->{ 'description' };
            delete $row->{ 'db_row_last_updated' };
            delete $row->{ 'disable_triggers' };

            for my $sentence ( @{ $row->{ 'story_sentences' } } )
            {
                delete $sentence->{ 'db_row_last_updated' };
                delete $sentence->{ 'disable_triggers' };
            }

        }
    }

    cmp_deeply( $actual_response, $expected_response );
}

test_stories_public();
test_stories_non_public();
test_tags();
test_media();
