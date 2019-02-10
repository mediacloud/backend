use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More tests => 76;
use Test::Deep;

use MediaWords::Test::API;
use MediaWords::Test::DB;

sub test_tag_sets($)
{
    my ( $db ) = @_;

    MediaWords::Test::API::setup_test_api_key( $db );

    # test for required fields errors
    MediaWords::Test::API::test_post( '/api/v2/tag_sets/create', { name  => 'foo' }, 1 );    # should require label
    MediaWords::Test::API::test_post( '/api/v2/tag_sets/create', { label => 'foo' }, 1 );    # should require name
    MediaWords::Test::API::test_put( '/api/v2/tag_sets/update', { name => 'foo' }, 1 );      # should require tag_sets_id

    # simple tag creation
    my $create_input = {
        name            => 'fooz tag set',
        label           => 'fooz label',
        description     => 'fooz description',
        show_on_media   => 1,
        show_on_stories => 1,
    };

    my $r = MediaWords::Test::API::test_post( '/api/v2/tag_sets/create', $create_input );
    MediaWords::Test::DB::validate_db_row( $db, 'tag_sets', $r->{ tag_set }, $create_input, 'create tag set' );

    # error on update non-existent tag
    MediaWords::Test::API::test_put( '/api/v2/tag_sets/update', { tag_sets_id => -1 }, 1 );

    # simple update
    my $update_input = {
        tag_sets_id     => $r->{ tag_set }->{ tag_sets_id },
        name            => 'barz tag',
        label           => 'barz label',
        description     => 'barz description',
        show_on_media   => 0,
        show_on_stories => 0,
    };

    $r = MediaWords::Test::API::test_put( '/api/v2/tag_sets/update', $update_input );
    MediaWords::Test::DB::validate_db_row( $db, 'tag_sets', $r->{ tag_set }, $update_input, 'update tag set' );

    my $tag_sets       = $db->query( "select * from tag_sets" )->hashes;
    my $got_tag_sets   = MediaWords::Test::API::test_get( '/api/v2/tag_sets/list' );
    my $tag_set_fields = [ qw/name label description show_on_media show_on_stories/ ];
    MediaWords::Test::DB::rows_match( "tag_sets/list", $got_tag_sets, $tag_sets, 'tag_sets_id', $tag_set_fields );

    my $tag_set = $tag_sets->[ 0 ];
    $got_tag_sets = MediaWords::Test::API::test_get( '/api/v2/tag_sets/single/' . $tag_set->{ tag_sets_id }, {} );
    MediaWords::Test::DB::rows_match( "tag_sets/single", $got_tag_sets, [ $tag_set ], 'tag_sets_id', $tag_set_fields );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database( \&test_tag_sets );
}

main();
