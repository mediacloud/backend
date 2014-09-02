package MediaWords::Test::DB;

# database utility functions for testing.  includes functionality to run tests on a temporary db

use strict;
use warnings;

use File::Path;

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::Pg::Schema;
use MediaWords::Util::Config;

# create a new database to use for testing; execute the schema definition sql
sub _create_test_database
{
    my $base_db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    my $test_db_name = 'mediacloud_test_' . time() . '_' . $$;

    # print "creating database $test_db_name ...\n";
    $base_db->query( "create database $test_db_name" );

    $base_db->disconnect();

    my $test_connect_info = [ MediaWords::DB::connect_info ];
    $test_connect_info->[ 0 ] =~ s/dbname=[a-z0-9_]*/dbname=$test_db_name/i;

    # print "connecting to test database: $test_connect_info->[0] ...\n";
    my $test_db = DBIx::Simple::MediaWords->connect( @{ $test_connect_info } );

    if ( !open( FILE, "$FindBin::Bin/../script/mediawords.sql" ) )
    {
        die( "Unable to open schema file: $!" );
    }

    my $schema_sql = join( "\n", ( <FILE> ) );

    close( FILE );

    $test_db->query( $schema_sql );

    MediaWords::Pg::Schema::add_functions( $test_db );

    # make sure the stories table exists as a sanity check for the schema
    $test_db->query( "select * from stories" );

    return ( $test_db, $test_db_name, $test_connect_info );
}

# drop the test databse
sub _drop_test_database
{
    my ( $test_db_name ) = @_;

    my $base_db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    $base_db->query( "drop database $test_db_name" );
}

# run the given function on a temporary, clean database
sub test_on_test_database
{
    my ( $sub ) = @_;

    my $result = MediaWords::Pg::Schema::recreate_db( 'test' );

    die "Error recreating the test db" unless $result == 0;

    my $db = MediaWords::DB::connect_to_db( 'test' );
    eval { $sub->( $db ); };

    if ( $@ )
    {
        die( $@ );
    }

    if ( $db )
    {
        $db->disconnect();
    }
}

sub create_download_for_feed
{
    my ( $feed, $dbs ) = @_;

    my $priority = 0;
    if ( !$feed->{ last_attempted_download_time } )
    {
        $priority = 10;
    }

    my $host = lc( ( URI::Split::uri_split( $feed->{ url } ) )[ 1 ] );
    my $download = $dbs->create(
        'downloads',
        {
            feeds_id      => $feed->{ feeds_id },
            url           => $feed->{ url },
            host          => $host,
            type          => 'feed',
            sequence      => 1,
            state         => 'pending',
            priority      => $priority,
            download_time => 'now()',
            extracted     => 'f'
        }
    );

    return $download;
}

# create test medium with a simple label
sub create_test_medium
{
    my ( $db, $label ) = @_;

    return $db->create(
        'media',
        {
            name        => $label,
            url         => "http://media.test/$label",
            moderated   => 't',
            feeds_added => 't'
        }
    );
}

# create test feed with a simple label belonging to $medium
sub create_test_feed
{
    my ( $db, $label, $medium ) = @_;

    return $db->create(
        'feeds',
        {
            name     => $label,
            url      => "http://feed.test/$label",
            media_id => $medium->{ media_id }
        }
    );
}

# create test story with a simple label belonging to $feed
sub create_test_story
{
    my ( $db, $label, $feed ) = @_;

    my $story = $db->create(
        'stories',
        {
            media_id      => $feed->{ media_id },
            url           => "http://story/$label",
            guid          => "guid://story/$label",
            title         => "story $label",
            description   => "description $label",
            publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 100000 ),
            collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 200000 ),
            full_text_rss => 't'
        }
    );

    $db->query( <<END, $feed->{ feeds_id }, $story->{ stories_id } );
insert into feeds_stories_map ( feeds_id, stories_id ) values ( ?, ? )
END

    return $story;
}

# create structure of media, feeds, and stories from hash in the form
# { 'medium label a' =>
#     { 'feed label a' => [ 'story label a', 'story label b' ],
#       'feed label b' => [ 'story label c', 'story label d' ] } }
#
# returns the list of media sources created, with a feeds field on each medium and
# a stories field on each field, all referenced by the given labels
sub create_test_story_stack
{
    my ( $db, $data ) = @_;

    die( "invalid media data format" ) unless ( ref( $data ) eq 'HASH' );

    my $media = {};
    while ( my ( $medium_label, $feeds ) = each( %{ $data } ) )
    {
        my $medium = create_test_medium( $db, $medium_label );
        $media->{ $medium_label } = $medium;

        die( "invalid feeds data format" ) unless ( ref( $feeds ) eq 'HASH' );

        while ( my ( $feed_label, $story_labels ) = each( %{ $feeds } ) )
        {
            my $feed = create_test_feed( $db, $feed_label, $medium );
            $medium->{ feeds }->{ $feed_label } = $feed;

            die( "invalid stories data format" ) unless ( ref( $story_labels ) eq 'ARRAY' );

            for my $story_label ( @{ $story_labels } )
            {
                my $story = create_test_story( $db, $story_label, $feed );
                $feed->{ stories }->{ $story_label } = $story;
            }
        }
    }

    return $media;
}

1;
