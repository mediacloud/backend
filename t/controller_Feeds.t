use strict;
use warnings;
use Test::NoWarnings;
use Test::More tests => 3 + 1;

BEGIN { use_ok 'Catalyst::Test', 'MediaWords' }
BEGIN { use_ok 'MediaWords::Controller::Feeds' }

use MediaWords::DB;

sub main {
    my $db = MediaWords::DB::connect_to_db;
    my $medium = $db->query( "select * from media" )->hash;
    
    if ( $medium )
    {
        ok( request( '/feeds/list/$medium->{ media_id }' )->is_success, 'Request should succeed' );
    }
    else
    {
        my $id = "controller_Feeds test $$";
        my $medium = $db->create( 'media', { name => $id, url => $id, moderated => 't', feeds_added => 't' } );
        my $feed = $db->create( 'feeds', { name => $id, url => $id, media_id => $medium->{ media_id } } );
        
        ok( request( "/feeds/list/$medium->{ media_id }" )->is_success, 'Request should succeed' );

        $db->query( "delete from media where media_id = ?", $medium->{ media_id } );        
    }
}

main();
