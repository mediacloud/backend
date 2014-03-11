package MediaWords::Test::DB;

# database utility functions for testing.  includes functionality to run tests on a temporary db

use strict;

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

    print "creating database $test_db_name ...\n";
    $base_db->query( "create database $test_db_name" );

    $base_db->disconnect();

    my $test_connect_info = [ MediaWords::DB::connect_info ];
    $test_connect_info->[ 0 ] =~ s/dbname=[a-z0-9_]*/dbname=$test_db_name/i;

    print "connecting to test database: $test_connect_info->[0] ...\n";
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

1;
