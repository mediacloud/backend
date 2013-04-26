use strict;
use warnings;
use Test::NoWarnings;
use Test::More tests => 2 + 1;

BEGIN
{
    $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;
    use_ok 'Catalyst::Test', 'MediaWords';
}
BEGIN { use_ok 'MediaWords::Controller::Admin::Feeds' }

use MediaWords::DB;

sub main
{
    my $db     = MediaWords::DB::connect_to_db;
    my $medium = $db->query( "select * from media" )->hash;

    if ( $medium )
    {
        ok( request( '/admin/feeds/list/$medium->{ media_id }' )->is_success, 'Request should succeed' );
    }
    else
    {
        my $id     = "controller_Feeds test $$";
        my $medium = $db->create( 'media', { name => $id, url => $id, moderated => 't', feeds_added => 't' } );
        my $feed   = $db->create( 'feeds', { name => $id, url => $id, media_id => $medium->{ media_id } } );

        ok( request( "/admin/feeds/list/$medium->{ media_id }" )->is_success, 'Request should succeed' );

        $db->query( "delete from media where media_id = ?", $medium->{ media_id } );
    }
}

main();
