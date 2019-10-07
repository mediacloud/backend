use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::NoWarnings;
use Test::Deep;
use Test::More tests => 15;

use Readonly;
use HTTP::Status qw(:constants);
use HTTP::Response;
use Data::Dumper;

use MediaWords::DB;
use MediaWords::Test::HashServer;
use MediaWords::Test::URLs;
use MediaWords::Util::URL::Variants;
use MediaWords::Test::DB::Create;


Readonly my $TEST_HTTP_SERVER_PORT => 9998;

sub test_all_url_variants($)
{
    my ( $db ) = @_;

    my @actual_url_variants;
    my @expected_url_variants;

    # Undefined URL
    eval { MediaWords::Util::URL::Variants::all_url_variants( $db, undef ); };
    ok( $@, 'Undefined URL' );

    # Non-HTTP(S) URL
    Readonly my $gopher_url => 'gopher://gopher.floodgap.com/0/v2/vstat';
    @actual_url_variants = MediaWords::Util::URL::Variants::all_url_variants( $db, $gopher_url );
    @expected_url_variants = ( $gopher_url );
    is_deeply( [ sort @actual_url_variants ], [ sort @expected_url_variants ], 'Non-HTTP(S) URL' );

    # Basic test
    Readonly my $TEST_HTTP_SERVER_URL       => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    Readonly my $starting_url_without_cruft => $TEST_HTTP_SERVER_URL . '/first';
    Readonly my $cruft                      => '?utm_source=A&utm_medium=B&utm_campaign=C';
    Readonly my $starting_url               => $starting_url_without_cruft . $cruft;

    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third' . $cruft . '" />',
        '/third'  => 'This is where the redirect chain should end.',
    };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::Variants::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url, $starting_url_without_cruft,
        $TEST_HTTP_SERVER_URL . '/third',
        $TEST_HTTP_SERVER_URL . '/third' . $cruft
    );
    is_deeply( [ sort @actual_url_variants ], [ sort @expected_url_variants ], 'Basic all_url_variants() test' );

    # <link rel="canonical" />
    $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third' . $cruft . '" />',
        '/third'  => '<link rel="canonical" href="' . $TEST_HTTP_SERVER_URL . '/fourth" />',
    };

    $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::Variants::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url, $starting_url_without_cruft,
        $TEST_HTTP_SERVER_URL . '/third',
        $TEST_HTTP_SERVER_URL . '/third' . $cruft,
        $TEST_HTTP_SERVER_URL . '/fourth',
    );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        '<link rel="canonical" /> all_url_variants() test'
    );

    # Redirect to a homepage
    $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/',
    };

    $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::Variants::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url_without_cruft, $starting_url,
        $TEST_HTTP_SERVER_URL . '/second',
        $TEST_HTTP_SERVER_URL . '/second' . $cruft
    );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        '"Redirect to homepage" all_url_variants() test'
    );
}

sub test_all_url_variants_invalid_variants($)
{
    my ( $db ) = @_;

    my @actual_url_variants;
    my @expected_url_variants;

    # Invalid URL variant (suspended Twitter account)
    Readonly my $invalid_url_variant => 'https://twitter.com/Todd__Kincannon/status/518499096974614529';
    @actual_url_variants = MediaWords::Util::URL::Variants::all_url_variants( $db, $invalid_url_variant );
    @expected_url_variants = ( $invalid_url_variant );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        'Invalid URL variant (suspended Twitter account)'
    );
}

sub test_get_topic_url_variants
{
    my ( $db ) = @_;

    my $data = {
        A => {
            B => [ 1, 2, 3 ],
            C => [ 4, 5, 6 ]
        },
        D => { E => [ 7, 8, 9 ] }
    };

    my $media = MediaWords::Test::DB::Create::create_test_story_stack( $db, $data );

    my $story_1 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 1 };
    my $story_2 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 2 };
    my $story_3 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 3 };
    my $story_4 = $media->{ A }->{ feeds }->{ C }->{ stories }->{ 4 };

    $db->query( <<END, $story_2->{ stories_id }, $story_1->{ stories_id } );
insert into topic_merged_stories_map ( source_stories_id, target_stories_id ) values( ?, ? )
END
    $db->query( <<END, $story_3->{ stories_id }, $story_2->{ stories_id } );
insert into topic_merged_stories_map ( source_stories_id, target_stories_id ) values( ?, ? )
END

    my $tag_set = $db->create( 'tag_sets', { name => 'foo' } );

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'foo' );

    $db->create(
        'topic_stories',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_4->{ stories_id }
        }
    );

    $db->create(
        'topic_stories',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_1->{ stories_id }
        }
    );

    $db->create(
        'topic_links',
        {
            topics_id      => $topic->{ topics_id },
            stories_id     => $story_4->{ stories_id },
            ref_stories_id => $story_1->{ stories_id },
            url            => $story_1->{ url },
            redirect_url   => $story_1->{ url } . "/redirect_url"
        }
    );

    $db->create(
        'topic_stories',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_2->{ stories_id }
        }
    );

    $db->create(
        'topic_links',
        {
            topics_id      => $topic->{ topics_id },
            stories_id     => $story_4->{ stories_id },
            ref_stories_id => $story_2->{ stories_id },
            url            => $story_2->{ url },
            redirect_url   => $story_2->{ url } . "/redirect_url"
        }
    );

    $db->create(
        'topic_stories',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_3->{ stories_id }
        }
    );

    $db->create(
        'topic_links',
        {
            topics_id      => $topic->{ topics_id },
            stories_id     => $story_4->{ stories_id },
            ref_stories_id => $story_3->{ stories_id },
            url            => $story_3->{ url } . '/alternate',
        }
    );

    my $expected_urls = [
        $story_1->{ url },
        $story_1->{ url } . '?utm_source=A&utm_medium=B&utm_campaign=C',
        $story_2->{ url },
        $story_1->{ url } . "/redirect_url",
        $story_2->{ url } . "/redirect_url",
        $story_3->{ url },
        $story_3->{ url } . "/alternate"
    ];

    my $test_url = $story_1->{ url } . '?utm_source=A&utm_medium=B&utm_campaign=C';
    my $url_variants = MediaWords::Util::URL::Variants::all_url_variants( $db, $test_url );

    $url_variants  = [ sort { $a cmp $b } @{ $url_variants } ];
    $expected_urls = [ sort { $a cmp $b } @{ $expected_urls } ];

    is( scalar( @{ $url_variants } ), scalar( @{ $expected_urls } ), 'test_get_topic_url_variants: same number variants' );

    for ( my $i = 0 ; $i < @{ $expected_urls } ; $i++ )
    {
        is_urls( $url_variants->[ $i ], $expected_urls->[ $i ], 'test_get_topic_url_variants: url variant match $i' );
    }
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    my $db = MediaWords::DB::connect_to_db();

    test_all_url_variants( $db );
    test_all_url_variants_invalid_variants( $db );
    test_get_topic_url_variants( $db );
}

main();
