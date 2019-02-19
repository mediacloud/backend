use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::Test::API;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

# return tag in either { tags_id => $tags_id }
# or { tag => $tag, tag_set => $tag_set } form depending on $input_form
sub _get_put_tag_input_tag($$$)
{
    my ( $tag, $tag_set, $input_form ) = @_;

    if ( $input_form eq 'id' )
    {
        return { tags_id => $tag->{ tags_id } };
    }
    elsif ( $input_form eq 'name' )
    {
        return { tag => $tag->{ tag }, tag_set => $tag_set->{ name } };
    }
    else
    {
        die( "unknown input_form '$input_form'" );
    }
}

# given a set of tags, return a list of hashes in the proper form for a put_tags call
sub _get_put_tag_input_records($$$$$$)
{
    my ( $db, $table, $rows, $tag_sets, $input_form, $action ) = @_;

    my $id_field = $table . "_id";

    my $input = [];
    for my $add_tag_set ( @{ $tag_sets } )
    {
        for my $add_tag ( @{ $add_tag_set->{ add_tags } } )
        {
            for my $row ( @{ $rows } )
            {
                my $put_tag = _get_put_tag_input_tag( $add_tag, $add_tag_set, $input_form );
                $put_tag->{ $id_field } = $row->{ $id_field };
                $put_tag->{ action } = $action;

                push( @{ $input }, $put_tag );
            }
        }
    }

    return $input;
}

# get the url for the put_tag end point for the given table
sub _get_put_tag_url($;$)
{
    my ( $table, $clear ) = @_;

    my $url = "/api/v2/$table/put_tags";

    $url .= '?clear_tag_sets=1' if ( $clear );

    return $url;
}

# test using put_tags to add the given tags to the given rows in the given table.
sub test_add_tags
{
    my ( $db, $table, $rows, $tag_sets, $input_form, $clear ) = @_;

    my $num_add_tag_sets = int( scalar( @{ $tag_sets } ) / 2 );
    my $num_add_tags     = int( scalar( @{ $tag_sets->[ 0 ]->{ tags } } ) / 2 );

    my $add_tag_sets = [ @{ $tag_sets }[ 0 .. $num_add_tag_sets - 1 ] ];
    map { $_->{ add_tags } = [ @{ $_->{ tags } }[ 0 .. $num_add_tags - 1 ] ] } @{ $add_tag_sets };

    my $put_tags = _get_put_tag_input_records( $db, $table, $rows, $add_tag_sets, $input_form, 'add' );

    my $r = MediaWords::Test::API::test_put( _get_put_tag_url( $table, $clear ), $put_tags );

    my $map_table    = $table . "_tags_map";
    my $id_field     = $table . "_id";
    my $row_ids      = [ map { $_->{ $id_field } } @{ $rows } ];
    my $row_ids_list = join( ',', @{ $row_ids } );

    my $add_tags = [];
    map { push( @{ $add_tags }, @{ $_->{ add_tags } } ) } @{ $add_tag_sets };

    my $clear_label = $clear ? 'clear' : 'no clear';
    my $label =
      "test add tags $table with $clear_label input $input_form [" .
      scalar( @{ $rows } ) . " rows / " .
      scalar( @{ $add_tags } ) . " add tags]";

    my $tags_ids_list = join( ',', map { $_->{ tags_id } } @{ $add_tags } );

    my ( $map_count ) = $db->query( <<SQL )->flat;
select count(*) from $map_table where $id_field in ( $row_ids_list ) and tags_id in ( $tags_ids_list )
SQL

    my $expected_map_count = scalar( @{ $rows } ) * scalar( @{ $add_tags } );
    is( $map_count, $expected_map_count, "$label map count" );

    my $maps = $db->query( <<SQL )->hashes;
select * from $map_table where $id_field in ( $row_ids_list ) and tags_id in ( $tags_ids_list )
SQL
    for my $map ( @{ $maps } )
    {
        my $row_expected = grep { $map->{ $id_field } == $_->{ $id_field } } @{ $rows };
        ok( $row_expected, "$label expected row $map->{ $id_field }" );

        my $tag_expected = grep { $map->{ $id_field } == $_->{ $id_field } } @{ $rows };
        ok( $tag_expected, "$label expected tag $map->{ tags_id }" );
    }

    # clean up so the next test has a clean slate
    $db->query( "delete from $map_table where $id_field in ( $row_ids_list ) and tags_id in ( $tags_ids_list )" );
}

# test removing tag associations
sub test_remove_tags
{
    my ( $db, $table, $rows, $tag_sets, $input_form ) = @_;

    my $map_table         = $table . "_tags_map";
    my $id_field          = $table . "_id";
    my $row_ids           = [ map { $_->{ $id_field } } @{ $rows } ];
    my $row_ids_list      = join( ',', @{ $row_ids } );
    my $tag_sets_ids_list = join( ',', map { $_->{ tag_sets_id } } @{ $tag_sets } );

    my $label = "test remove tags $table input $input_form";

    for my $row ( @{ $rows } )
    {
        $db->query( <<SQL, $row->{ $id_field } );
insert into $map_table ( $id_field, tags_id )
        select \$1, tags_id from tags where tag_sets_id in ( $tag_sets_ids_list )
SQL
    }

    map { $_->{ add_tags } = [ $_->{ tags }->[ 0 ] ] } @{ $tag_sets };

    my $put_tags = _get_put_tag_input_records( $db, $table, $rows, $tag_sets, $input_form, 'remove' );
    my $r = MediaWords::Test::API::test_put( _get_put_tag_url( $table ), $put_tags );

    my $expected_map_count =
      scalar( @{ $tag_sets } ) * ( scalar( @{ $tag_sets->[ 0 ]->{ tags } } ) - 1 ) * scalar( @{ $rows } );

    my ( $map_count ) = $db->query( <<SQL )->flat;
select count(*)
    from $map_table join tags using ( tags_id )
    where $id_field in ( $row_ids_list ) and tag_sets_id in ( $tag_sets_ids_list )
SQL
    is( $map_count, $expected_map_count, "$label map count" );

    # clean up so the next test has a clean slate
    $db->query( <<SQL );
delete from $map_table
    using tags
    where $map_table.tags_id = tags.tags_id and
        $id_field in ( $row_ids_list ) and
        tag_sets_id in ( $tag_sets_ids_list )
SQL
}

# add all tags to the map, use the clear_tags= param, then make sure only added tags are associated
sub test_clear_tags($$$$$)
{
    my ( $db, $table, $rows, $tag_sets, $input_form ) = @_;

    my $map_table = $table . "_tags_map";
    my $id_field  = $table . "_id";

    my $tag_sets_ids_list = join( ',', map { $_->{ tag_sets_id } } @{ $tag_sets } );

    for my $row ( @{ $rows } )
    {
        $db->query( <<SQL, $row->{ $id_field } );
insert into $map_table ( $id_field, tags_id )
        select \$1, tags_id from tags where tag_sets_id in ( $tag_sets_ids_list )
SQL
    }

    test_add_tags( $db, $table, $rows, $tag_sets, $input_form, 1 );
}

# test /apiv/2/$table/put_tags call.  assumes that there are at least three
# rows in $table, which there should be from the create_test_story_stack() call
sub test_put_tags($$)
{
    my ( $db, $table ) = @_;

    my $url      = _get_put_tag_url( $table );
    my $id_field = $table . "_id";

    my $num_tag_sets = 5;
    my $num_tags     = 10;

    my $tag_sets = [];
    for my $i ( 1 .. $num_tag_sets )
    {
        my $tag_set = $db->find_or_create( 'tag_sets', { name => "put tags $i" } );
        for my $i ( 1 .. $num_tags )
        {
            my $tag = $db->find_or_create( 'tags', { tag => "tag $i", tag_sets_id => $tag_set->{ tag_sets_id } } );
            push( @{ $tag_set->{ tags } }, $tag );
        }
        push( @{ $tag_sets }, $tag_set );
    }

    my $first_tags_id = $tag_sets->[ 0 ]->{ tags }->[ 0 ];

    my $num_rows = 3;
    my $rows     = $db->query( "select * from $table limit $num_rows" )->hashes;

    my $first_row_id = $rows->[ 0 ]->{ "${ table }_id" };

    # test that api recognizes various errors
    MediaWords::Test::API::test_put( $url, {}, 1 );    # require list
    MediaWords::Test::API::test_put( $url, [ [] ], 1 );    # require list of records
    MediaWords::Test::API::test_put( $url, [ { tags_id   => $first_tags_id } ], 1 );    # require id
    MediaWords::Test::API::test_put( $url, [ { $id_field => $first_row_id } ],  1 );    # require tag

    test_add_tags( $db, $table, $rows, $tag_sets, 'id' );
    test_add_tags( $db, $table, $rows, $tag_sets, 'name' );
    test_remove_tags( $db, $table, $rows, $tag_sets, 'id' );

    test_clear_tags( $db, $table, $rows, $tag_sets, 'id' );
}

# test tags/list
sub test_tags_list($)
{
    my ( $db ) = @_;

    my $num_tags = 10;
    my $label    = "tags list";

    my $tag_set     = $db->create( 'tag_sets', { name => 'tag list test' } );
    my $tag_sets_id = $tag_set->{ tag_sets_id };
    my $input_tags  = [ map { { tag => "tag $_", label => "tag $_", tag_sets_id => $tag_sets_id } } ( 1 .. $num_tags ) ];
    map { MediaWords::Test::API::test_post( '/api/v2/tags/create', $_ ) } @{ $input_tags };

    # query by tag_sets_id
    my $got_tags = MediaWords::Test::API::test_get( '/api/v2/tags/list', { tag_sets_id => $tag_sets_id } );
    is( scalar( @{ $got_tags } ), $num_tags, "$label number of tags" );

    for my $got_tag ( @{ $got_tags } )
    {
        my ( $input_tag ) = grep { $got_tag->{ tag } eq $_->{ tag } } @{ $input_tags };
        ok( $input_tag, "$label found input tag" );
        map { is( $got_tag->{ $_ }, $input_tag->{ $_ }, "$label field $_" ) } keys( %{ $input_tag } );
    }

    my ( $t0, $t1, $t2, $t3 ) = @{ $got_tags };

    # test public= query
    MediaWords::Test::API::test_put( '/api/v2/tags/update', { tags_id => $t0->{ tags_id }, show_on_media   => 1 } );
    MediaWords::Test::API::test_put( '/api/v2/tags/update', { tags_id => $t1->{ tags_id }, show_on_stories => 1 } );
    my $got_public_tags = MediaWords::Test::API::test_get( '/api/v2/tags/list', { public => 1, tag_sets_id => $tag_sets_id } );
    is( scalar( @{ $got_public_tags } ), 2, "$label show_on_media count" );
    ok( ( grep { $_->{ tags_id } == $t0->{ tags_id } } @{ $got_public_tags } ), "$label public show_on_media" );
    ok( ( grep { $_->{ tags_id } == $t1->{ tags_id } } @{ $got_public_tags } ), "$label public show_on_stories" );

    # test similar_tags_id
    my $medium = $db->query( "select * from media limit 1" )->hash;
    map { $db->create( 'media_tags_map', { media_id => $medium->{ media_id }, tags_id => $_->{ tags_id } } ) }
      ( $t0, $t1, $t2 );
    my $got_similar_tags = MediaWords::Test::API::test_get( '/api/v2/tags/list', { similar_tags_id => $t0->{ tags_id } } );
    is( scalar( @{ $got_similar_tags } ), 2, "$label similar count" );
    ok( ( grep { $_->{ tags_id } == $t1->{ tags_id } } @{ $got_similar_tags } ), "$label similar tags_id t1" );
    ok( ( grep { $_->{ tags_id } == $t2->{ tags_id } } @{ $got_similar_tags } ), "$label simlar tags_id t2" );
}

# test tags/single
sub test_tags_single($)
{
    my ( $db ) = @_;

    my $label = "tags/single";

    my $expected_tag = $db->query( "select * from tags order by tags_id limit 1" )->hash;

    my $got_tags = MediaWords::Test::API::test_get( '/api/v2/tags/single/' . $expected_tag->{ tags_id } );

    my $got_tag = $got_tags->[ 0 ];

    ok( $got_tag, "$label found tag" );

    my $fields = [ qw/tags_id tag_sets_id tag label description show_on_media show_on_stories is_static/ ];
    map { is( $got_tag->{ $_ }, $expected_tag->{ $_ }, "$label field $_" ) } @{ $fields };
}

# test tags create, update, list, and association
sub test_tags($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    $media = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    # test for required fields errors
    MediaWords::Test::API::test_post( '/api/v2/tags/create', { tag   => 'foo' }, 1 );    # should require label
    MediaWords::Test::API::test_post( '/api/v2/tags/create', { label => 'foo' }, 1 );    # should require tag
    MediaWords::Test::API::test_put( '/api/v2/tags/update', { tag => 'foo' }, 1 );       # should require tags_id

    my $tag_set   = $db->create( 'tag_sets', { name => 'foo tag set' } );
    my $tag_set_b = $db->create( 'tag_sets', { name => 'bar tag set' } );

    # simple tag creation
    my $create_input = {
        tag_sets_id     => $tag_set->{ tag_sets_id },
        tag             => 'foo tag',
        label           => 'foo label',
        description     => 'foo description',
        show_on_media   => 1,
        show_on_stories => 1,
        is_static       => 1
    };

    my $r = MediaWords::Test::API::test_post( '/api/v2/tags/create', $create_input );
    MediaWords::Test::API::validate_db_row( $db, 'tags', $r->{ tag }, $create_input, 'create tag' );

    # error on update non-existent tag
    MediaWords::Test::API::test_put( '/api/v2/tags/update', { tags_id => -1 }, 1 );

    # simple update
    my $update_input = {
        tags_id         => $r->{ tag }->{ tags_id },
        tag_sets_id     => $tag_set_b->{ tag_sets_id },
        tag             => 'bar tag',
        label           => 'bar label',
        description     => 'bar description',
        show_on_media   => 0,
        show_on_stories => 0,
        is_static       => 0
    };

    $r = MediaWords::Test::API::test_put( '/api/v2/tags/update', $update_input );
    MediaWords::Test::API::validate_db_row( $db, 'tags', $r->{ tag }, $update_input, 'update tag' );

    # simple tags/list test
    test_tags_list( $db );
    test_tags_single( $db );

    # test put_tags calls on all tables
    test_put_tags( $db, 'stories' );
    test_put_tags( $db, 'media' );
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_tags,
        [ 'solr_standalone', 'job_broker:rabbitmq', 'rescrape_media' ] );

    done_testing();
}

main();
