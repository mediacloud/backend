use strict;
use warnings;

use Test::More;

use Data::Dumper;

use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories::ExtractorArguments;
use MediaWords::Test::DB;
use MediaWords::Util::URL;

sub add_download_to_story
{
    my ( $db, $feed, $story ) = @_;

    my $download = {
        feeds_id   => $feed->{ feeds_id },
        stories_id => $story->{ stories_id },
        url        => $story->{ url },
        host       => MediaWords::Util::URL::get_url_host( $story->{ url } ),
        type       => 'content',
        sequence   => 1,
        state      => 'success',
        path       => 'content:pending',
        priority   => 1,
        extracted  => 't'
    };

    $download = $db->create( 'downloads', $download );

    my $story_content = "$story->{ title }\n\n$story->{ description }";

    $download = MediaWords::DBI::Downloads::store_content( $db, $download, $story_content );

    $story->{ content }  = $story_content;
    $story->{ download } = $download;
}

sub get_cache_for_story
{
    my ( $db, $story ) = @_;

    my $downloads_id = $story->{ download }->{ downloads_id };

    my $c = $db->query( "select * from cached_extractor_results where downloads_id = ?", $downloads_id )->hash;

    return $c;
}

sub test_extractor_cache
{
    my ( $db ) = @_;

    my $data = MediaWords::Test::DB::Create::create_test_story_stack(
        $db,    #
        { medium => { feed => [ qw/story_1 story_2 story_3/ ] } },    #
    );

    my $medium  = $data->{ medium };
    my $feed    = $medium->{ feeds }->{ feed };
    my $story_1 = $feed->{ stories }->{ story_1 };
    my $story_2 = $feed->{ stories }->{ story_1 };
    my $story_3 = $feed->{ stories }->{ story_1 };

    map { add_download_to_story( $db, $feed, $_ ) } ( $story_1, $story_2, $story_3 );

    say STDERR "HELLO";

    my $xargs_nocache = MediaWords::DBI::Stories::ExtractorArguments->new( { use_cache => 0 } );

    say STDERR "HELLO 3";

    my $xargs_usecache = MediaWords::DBI::Stories::ExtractorArguments->new( { use_cache => 1 } );

    my $res = MediaWords::DBI::Downloads::extract( $db, $story_1->{ download }, $xargs_nocache );
    is( $res->{ extracted_html }, $story_1->{ content }, "uncached extraction - extractor result" );

    my $c = get_cache_for_story( $db, $story_1 );
    ok( !$c, "uncached extraction - no cache entry" );

    $res = MediaWords::DBI::Downloads::extract( $db, $story_1->{ download }, $xargs_usecache );
    is( $res->{ extracted_html }, $story_1->{ content }, "cached extraction 1 - extractor result" );

    $c = get_cache_for_story( $db, $story_1 );
    ok( $c, "cached extraction 1 - cache entry exits" );
    is( $c->{ extracted_html }, $story_1->{ content }, "cached extract 1 - cache result" );

    my $new_story_1_content = 'foo bar';
    $story_1->{ download } = MediaWords::DBI::Downloads::store_content( $db, $story_1->{ download }, $new_story_1_content );

    $res = MediaWords::DBI::Downloads::extract( $db, $story_1->{ download }, $xargs_usecache );
    is( $res->{ extracted_html }, $story_1->{ content }, "cached extraction 2 - extractor result" );

    $res = MediaWords::DBI::Downloads::extract( $db, $story_1->{ download }, $xargs_nocache );
    is( $res->{ extracted_html }, $new_story_1_content, "uncached extraction 2 - extractor result" );

    $res = MediaWords::DBI::Downloads::extract( $db, $story_2->{ download }, $xargs_usecache );
    is( $res->{ extracted_html }, $story_2->{ content }, "cached extraction 3 - extractor result" );

    $c = get_cache_for_story( $db, $story_2 );
    ok( $c, "cached extraction 3 - cache entry exits" );
    is( $c->{ extracted_html }, $story_2->{ content }, "cached extract 3 - cache result" );

}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;

            test_extractor_cache( $db );
        }
    );

    done_testing;
}

main();
