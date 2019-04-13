#
# Basic sanity test of extractor functionality
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More tests => 13;
use Test::NoWarnings;

use MediaWords::DB;
use MediaWords::DBI::Downloads::Store;
use MediaWords::DBI::Downloads::Extract;
use MediaWords::DBI::Stories::Extract;
use MediaWords::DBI::Stories::ExtractorArguments;
use MediaWords::DBI::Stories;
use MediaWords::Test::Data;
use MediaWords::Test::Text;
use MediaWords::Util::URL;

use Data::Dumper;
use File::Slurp;
use Readonly;

sub test_extract_content($$$)
{
    my ( $test_dataset, $file, $title ) = @_;

    my $test_stories = MediaWords::Test::Data::fetch_test_data_from_individual_files( "crawler_stories/$test_dataset" );

    my $test_story_hash;
    map { $test_story_hash->{ $_->{ title } } = $_ } @{ $test_stories };

    my $story = $test_story_hash->{ $title };

    die "story '$title' not found " unless $story;

    my $data_files_path = MediaWords::Test::Data::get_path_to_data_files( 'crawler/' . $test_dataset );
    my $path            = $data_files_path . '/' . $file;

    my $content = MediaWords::Util::Text::decode_from_utf8( read_file( $path ) );

    my $results = MediaWords::DBI::Downloads::Extract::extract_content( $content );

    my $extracted_text = $results->{ extracted_text };

    ok( length( $extracted_text ) > 7000, "Extracted text length looks reasonable" );
    ok( index( $extracted_text, '<' ) == -1, "No HTML tags left in extracted text" );
}

sub _add_download_to_story
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

    $download = MediaWords::DBI::Downloads::Store::store_content( $db, $download, $story_content );

    $story->{ content }  = $story_content;
    $story->{ download } = $download;
}

sub _get_cache_for_story
{
    my ( $db, $story ) = @_;

    my $downloads_id = $story->{ download }->{ downloads_id };

    my $c = $db->query( "select * from cache.extractor_results_cache where downloads_id = ?", $downloads_id )->hash;

    return $c;
}

sub test_extract($)
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

    map { _add_download_to_story( $db, $feed, $_ ) } ( $story_1, $story_2, $story_3 );

    my $xargs_nocache = MediaWords::DBI::Stories::ExtractorArguments->new( { use_cache => 0 } );

    my $xargs_usecache = MediaWords::DBI::Stories::ExtractorArguments->new( { use_cache => 1 } );

    my $res = MediaWords::DBI::Downloads::Extract::extract( $db, $story_1->{ download }, $xargs_nocache );
    is( $res->{ extracted_html }, $story_1->{ content }, "uncached extraction - extractor result" );

    my $c = _get_cache_for_story( $db, $story_1 );
    ok( !$c, "uncached extraction - no cache entry" );

    $res = MediaWords::DBI::Downloads::Extract::extract( $db, $story_1->{ download }, $xargs_usecache );
    is( $res->{ extracted_html }, $story_1->{ content }, "cached extraction 1 - extractor result" );

    $c = _get_cache_for_story( $db, $story_1 );
    ok( $c, "cached extraction 1 - cache entry exits" );
    is( $c->{ extracted_html }, $story_1->{ content }, "cached extract 1 - cache result" );

    my $new_story_1_content = 'foo bar';
    $story_1->{ download } = MediaWords::DBI::Downloads::Store::store_content( $db, $story_1->{ download }, $new_story_1_content );

    $res = MediaWords::DBI::Downloads::Extract::extract( $db, $story_1->{ download }, $xargs_usecache );
    is( $res->{ extracted_html }, $story_1->{ content }, "cached extraction 2 - extractor result" );

    $res = MediaWords::DBI::Downloads::Extract::extract( $db, $story_1->{ download }, $xargs_nocache );
    is( $res->{ extracted_html }, $new_story_1_content, "uncached extraction 2 - extractor result" );

    $res = MediaWords::DBI::Downloads::Extract::extract( $db, $story_2->{ download }, $xargs_usecache );
    is( $res->{ extracted_html }, $story_2->{ content }, "cached extraction 3 - extractor result" );

    $c = _get_cache_for_story( $db, $story_2 );
    ok( $c, "cached extraction 3 - cache entry exits" );
    is( $c->{ extracted_html }, $story_2->{ content }, "cached extract 3 - cache result" );
}

sub main
{
    # Errors might want to print out UTF-8 characters
    binmode( STDERR, ':utf8' );
    binmode( STDOUT, ':utf8' );
    my $builder = Test::More->builder;

    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    my $db = MediaWords::DB::connect_to_db();

    test_extract_content( 'gv', 'index_1.html', 'Brazil: Amplified conversations to fight the Digital Crimes Bill' );

    test_extract( $db );
}

main();
