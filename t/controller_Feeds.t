use strict;
use warnings;
use Test::NoWarnings;
use Test::More tests => 2;

# BEGIN { use Catalyst::Test 'MediaWords' };
BEGIN { use_ok 'MediaWords::Controller::Admin::Feeds' };

# commented out until we can add support for testing with auth -hal
# use MediaWords::DB;
# 
# sub main
# {
#     my $db     = MediaWords::DB::connect_to_db;
#     
#     my $id     = "controller_Feeds test $$";
#     
#     my $medium = $db->create( 'media', { name => $id, url => $id, moderated => 't', feeds_added => 't' } );
#     my $feed   = $db->create( 'feeds', { name => $id, url => $id, media_id => $medium->{ media_id } } );
#     
#     my ( 
# 
#     ok( request( "/admin/feeds/list/$medium->{ media_id }" )->is_success, 'Request should succeed' );
# 
#     $db->query( "delete from media where media_id = ?", $medium->{ media_id } );    
# }
# 
# main();
