use strict;
use warnings;
use utf8;

use Test::More tests => 20 + 1;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
    use lib "$FindBin::Bin/../";
}

use MediaWords::KeyValueStore::PostgreSQL;
use MediaWords::Test::DB;
use Data::Dumper;

use constant MOCK_DOWNLOADS_ID => 12345;

BEGIN
{
    use_ok( 'MediaWords::DB' );
}

sub _create_mock_download($$)
{
    my ( $db, $downloads_id ) = @_;

    $db->query(
        <<EOF
		INSERT INTO media (media_id, url, name, moderated)
		VALUES (1, 'http://', 'Test Media', 't')
EOF
    );

    $db->query(
        <<EOF
		INSERT INTO feeds(feeds_id, media_id, name, url)
		VALUES (1, 1, 'Test Feed', 'http://')
EOF
    );

    $db->query(
        <<EOF
		INSERT INTO stories (stories_id, media_id, url, guid, title, publish_date, collect_date)
		VALUES (1, 1, 'http://', 'guid', 'Test Story', now(), now());
EOF
    );

    $db->query(
        <<EOF,
		INSERT INTO downloads (downloads_id, feeds_id, stories_id, url, host, download_time, type, state, priority, sequence)
		VALUES (?, 1, 1, 'http://', '', now(), 'content', 'pending', 0, 0);
EOF
        $downloads_id
    );
}

sub test_store_content($$)
{
    my ( $db, $postgresql ) = @_;

    my $test_downloads_id   = MOCK_DOWNLOADS_ID + 0;
    my $test_downloads_path = undef;
    my $test_content        = 'Media Cloud - pnoןɔ ɐıpǝɯ';    # UTF-8
    my $content_ref;

    # Store content
    my $postgresql_id;
    eval { $postgresql_id = $postgresql->store_content( $db, $test_downloads_id, \$test_content ); };
    ok( ( !$@ ), "Storing content failed: $@" );
    ok( $postgresql_id,                                     'Object ID was returned' );
    ok( length( $postgresql_id ) > length( 'postgresql:' ), 'Object ID is of the valid size' );

    # Fetch content
    eval { $content_ref = $postgresql->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( ( !$@ ), "Fetching download failed: $@" );
    ok( $content_ref, "Fetching download did not die but no content was returned" );
    is( $$content_ref, $test_content, "Content doesn't match." );

    # Check if GridFS thinks that the content exists
    ok(
        $postgresql->content_exists( $db, $test_downloads_id, $test_downloads_path ),
        "content_exists() reports that content doesn't exist (although it does)"
    );

    # Remove content, try fetching again
    $postgresql->remove_content( $db, $test_downloads_id, $test_downloads_path );
    $content_ref = undef;
    eval { $content_ref = $postgresql->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( $@, "Fetching download that does not exist should have failed" );
    ok( ( !$content_ref ),
        "Fetching download that does not exist failed (as expected) but the content reference was returned" );

    # Check if GridFS thinks that the content exists
    ok(
        ( !$postgresql->content_exists( $db, $test_downloads_id, $test_downloads_path ) ),
        "content_exists() reports that content exists (although it doesn't)"
    );
}

sub test_store_content_twice($$)
{
    my ( $db, $postgresql ) = @_;

    my $test_downloads_id   = MOCK_DOWNLOADS_ID + 0;
    my $test_downloads_path = undef;
    my $test_content        = 'Loren ipsum dolor sit amet.';
    my $content_ref;

    # Store content
    my $postgresql_id;
    eval {
        $postgresql_id = $postgresql->store_content( $db, $test_downloads_id, \$test_content );
        $postgresql_id = $postgresql->store_content( $db, $test_downloads_id, \$test_content );
    };
    ok( ( !$@ ), "Storing content failed: $@" );
    ok( $postgresql_id,                                     'Object ID was returned' );
    ok( length( $postgresql_id ) > length( 'postgresql:' ), 'Object ID is of the valid size' );

    # Fetch content
    eval { $content_ref = $postgresql->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( ( !$@ ), "Fetching download failed: $@" );
    ok( $content_ref, "Fetching download did not die but no content was returned" );
    is( $$content_ref, $test_content, "Content doesn't match." );

    # Check if GridFS thinks that the content exists
    ok(
        $postgresql->content_exists( $db, $test_downloads_id, $test_downloads_path ),
        "content_exists() reports that content doesn't exist (although it does)"
    );

    # Remove content, try fetching again
    $postgresql->remove_content( $db, $test_downloads_id, $test_downloads_path );
    $content_ref = undef;
    eval { $content_ref = $postgresql->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
    ok( $@, "Fetching download that does not exist should have failed" );
    ok( ( !$content_ref ),
        "Fetching download that does not exist failed (as expected) but the content reference was returned" );

    # Check if GridFS thinks that the content exists
    ok(
        ( !$postgresql->content_exists( $db, $test_downloads_id, $test_downloads_path ) ),
        "content_exists() reports that content exists (although it doesn't)"
    );
}

sub main()
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            # Errors might want to print out UTF-8 characters
            binmode( STDERR, ':utf8' );
            binmode( STDOUT, ':utf8' );
            my $builder = Test::More->builder;

            binmode $builder->output,         ":utf8";
            binmode $builder->failure_output, ":utf8";
            binmode $builder->todo_output,    ":utf8";

            my $postgresql = MediaWords::KeyValueStore::PostgreSQL->new(
                {
                    database_label => undef,              # default database
                    table          => 'raw_downloads',    #
                }
            );

            _create_mock_download( $db, MOCK_DOWNLOADS_ID );

            test_store_content( $db, $postgresql );
            test_store_content_twice( $db, $postgresql );
        }
    );
}

main();
