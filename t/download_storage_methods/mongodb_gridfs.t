use strict;
use warnings;

use Test::More;

use Data::Dumper;
use MongoDB;
use MongoDB::GridFS;
use MediaWords::KeyValueStore::GridFS;
use MediaWords::DB;
use MediaWords::Util::Config;
use IO::Socket;

sub host_port_is_available($$)
{
    my ( $host, $port ) = @_;

    my $socket = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port,
        Proto    => 'tcp',
        Type     => SOCK_STREAM
    );
    if ( $socket )
    {
        close( $socket );
        return 1;
    }
    else
    {
        return 0;
    }
}

my $config = MediaWords::Util::Config::get_config;
unless ( $config->{ mongodb_gridfs }->{ test } )
{
    plan skip_all => "MongoDB's testing database is not configured";
}
else
{
    unless ( host_port_is_available( $config->{ mongodb_gridfs }->{ host }, $config->{ mongodb_gridfs }->{ port } ) )
    {
        # Skipping test if "mongod" is not running because the point of this test is to validate
        # download storage handler and not service availability
        plan skip_all => "Unable to connect to MongoDB's testing database";
    }
    else
    {
        plan tests => 20;
    }
}

my $gridfs =
  MediaWords::KeyValueStore::GridFS->new( { database_name => $config->{ mongodb_gridfs }->{ test }->{ database_name } } );
ok( $gridfs, "MongoDB initialized" );

my $db = MediaWords::DB::connect_to_db;
ok( $db, "PostgreSQL initialized " );

my $test_downloads_id   = 999999999999999;
my $test_downloads_path = undef;
my $test_content        = 'Loren ipsum dolor sit amet.';
my $content_ref;

#
# Store content
#

my $gridfs_id;
eval { $gridfs_id = $gridfs->store_content( $db, $test_downloads_id, \$test_content ); };
ok( ( !$@ ), "Storing content failed: $@" );
ok( $gridfs_id,                                                          'Object ID was returned' );
ok( length( $gridfs_id ) == length( 'gridfs:5152138e3e7062d55800057c' ), 'Object ID is of the valid size' );

#
# Fetch content, compare
#

eval { $content_ref = $gridfs->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
ok( ( !$@ ), "Fetching download failed: $@" );
ok( $content_ref, "Fetching download did not die but no content was returned" );
is( $$content_ref, $test_content, "Content doesn't match." );

#
# Remove content, try fetching again
#

$gridfs->remove_content( $db, $test_downloads_id, $test_downloads_path );
$content_ref = undef;
eval { $content_ref = $gridfs->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
ok( $@, "Fetching download that does not exist should have failed" );
ok( ( !$content_ref ), "Fetching download that does not exist failed (as expected) but the content reference was returned" );

#
# Check GridFS thinks that the content exists
#
ok(
    ( !$gridfs->content_exists( $db, $test_downloads_id, $test_downloads_path ) ),
    "content_exists() reports that content exists (although it shouldn't)"
);

#
# Store content twice
#

$gridfs_id = undef;
eval {
    $gridfs_id = $gridfs->store_content( $db, $test_downloads_id, \$test_content );
    $gridfs_id = $gridfs->store_content( $db, $test_downloads_id, \$test_content );
};
ok( ( !$@ ), "Storing content twice failed: $@" );
ok( $gridfs_id,                                                          'Object ID was returned' );
ok( length( $gridfs_id ) == length( 'gridfs:5152138e3e7062d55800057c' ), 'Object ID is of the valid size' );

# Fetch content again, compare
eval { $content_ref = $gridfs->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
ok( ( !$@ ), "Fetching download failed: $@" );
ok( $content_ref, "Fetching download did not die but no content was returned" );
is( $$content_ref, $test_content, "Content doesn't match." );

# Remove content, try fetching again
$gridfs->remove_content( $db, $test_downloads_id, $test_downloads_path );
$content_ref = undef;
eval { $content_ref = $gridfs->fetch_content( $db, $test_downloads_id, $test_downloads_path ); };
ok( $@, "Fetching download that does not exist should have failed" );
ok( ( !$content_ref ), "Fetching download that does not exist failed (as expected) but the content reference was returned" );

# Check GridFS thinks that the content exists
ok(
    ( !$gridfs->content_exists( $db, $test_downloads_id, $test_downloads_path ) ),
    "content_exists() reports that content exists (although it shouldn't)"
);
