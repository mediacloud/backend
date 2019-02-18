use strict;
use warnings;
use utf8;

use Test::More tests => 20 + 1;

use MediaWords::KeyValueStore::PostgreSQL;
use Data::Dumper;
use Readonly;

require "$FindBin::Bin/helpers/create_mock_download.inc.pl";

BEGIN
{
    use_ok( 'MediaWords::DB' );
}

sub test_store_content($$$)
{
    my ( $db, $postgresql, $test_downloads_id ) = @_;

    my $test_downloads_path = undef;
    my $test_content        = 'Media Cloud - pnoןɔ ɐıpǝɯ';    # UTF-8
    my $content;

    # Store content
    my $postgresql_id;
    eval { $postgresql_id = $postgresql->store_content( $db, $test_downloads_id, $test_content ); };
    ok( ( !$@ ), "Storing content failed: $@" );
    ok( $postgresql_id,                                     'Object ID was returned' );
    ok( length( $postgresql_id ) > length( 'postgresql:' ), 'Object ID is of the valid size' );

    # Fetch content
    eval { $content = $postgresql->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( ( !$@ ), "Fetching download failed: $@" );
    ok( defined $content, "Fetching download did not die but no content was returned" );
    is( $content, $test_content, "Content doesn't match." );

    # Check if PostgreSQL thinks that the content exists
    ok(
        $postgresql->content_exists( $db, $test_downloads_id, $test_downloads_path ),
        "content_exists() reports that content doesn't exist (although it does)"
    );

    # Remove content, try fetching again
    $postgresql->remove_content( $db, $test_downloads_id, $test_downloads_path );
    $content = undef;
    eval { $content = $postgresql->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( $@, "Fetching download that does not exist should have failed" );
    ok( ( !defined $content ),
        "Fetching download that does not exist failed (as expected) but the content was still returned" );

    # Check if PostgreSQL thinks that the content exists
    ok(
        ( !$postgresql->content_exists( $db, $test_downloads_id, $test_downloads_path ) ),
        "content_exists() reports that content exists (although it doesn't)"
    );
}

sub test_store_content_twice($$$)
{
    my ( $db, $postgresql, $test_downloads_id ) = @_;

    my $test_downloads_path = undef;
    my $test_content        = 'Loren ipsum dolor sit amet.';
    my $content;

    # Store content
    my $postgresql_id;
    eval {
        $postgresql_id = $postgresql->store_content( $db, $test_downloads_id, $test_content );
        $postgresql_id = $postgresql->store_content( $db, $test_downloads_id, $test_content );
    };
    ok( ( !$@ ), "Storing content failed: $@" );
    ok( $postgresql_id,                                     'Object ID was returned' );
    ok( length( $postgresql_id ) > length( 'postgresql:' ), 'Object ID is of the valid size' );

    # Fetch content
    eval { $content = $postgresql->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( ( !$@ ), "Fetching download failed: $@" );
    ok( defined $content, "Fetching download did not die but no content was returned" );
    is( $content, $test_content, "Content doesn't match." );

    # Check if PostgreSQL thinks that the content exists
    ok(
        $postgresql->content_exists( $db, $test_downloads_id, $test_downloads_path ),
        "content_exists() reports that content doesn't exist (although it does)"
    );

    # Remove content, try fetching again
    $postgresql->remove_content( $db, $test_downloads_id, $test_downloads_path );
    $content = undef;
    eval { $content = $postgresql->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( $@, "Fetching download that does not exist should have failed" );
    ok( ( !defined $content ),
        "Fetching download that does not exist failed (as expected) but the content was still returned" );

    # Check if PostgreSQL thinks that the content exists
    ok(
        ( !$postgresql->content_exists( $db, $test_downloads_id, $test_downloads_path ) ),
        "content_exists() reports that content exists (although it doesn't)"
    );
}

sub test_postgresql($$)
{
    my ( $db, $postgresql_handler ) = @_;

    # Errors might want to print out UTF-8 characters
    binmode( STDERR, ':utf8' );
    binmode( STDOUT, ':utf8' );

    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    my $test_downloads_id = create_mock_download( $db );

    test_store_content( $db, $postgresql_handler, $test_downloads_id );
    test_store_content_twice( $db, $postgresql_handler, $test_downloads_id );
}
