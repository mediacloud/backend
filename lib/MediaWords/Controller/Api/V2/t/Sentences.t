use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use MediaWords::Test::HTTP::HashServer;
use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::Test::API;
use MediaWords::Test::DB;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

sub test_sentences_count($)
{
    my ( $db ) = @_;

    my $label = "setences/count";

    my $stories = $db->query( "select * from stories order by stories_id asc limit 10" )->hashes;
    my $stories_ids = [ map { $_->{ stories_id } } @{ $stories } ];
    ok( scalar( @{ $stories_ids } ) );
    my $ss = $db->query( 'select * from story_sentences where stories_id in ( ?? )', @{ $stories_ids } )->hashes;

    my $stories_ids_list = join( ' ', @{ $stories_ids } );
    my $r = test_get( '/api/v2/sentences/count', { q => "stories_id:($stories_ids_list)" } );

    # we import titles as sentences as well as the sentences themselves, so expect them in the count
    my $expected_count = scalar( @{ $ss } ) + 10;

    is( $r->{ count }, $expected_count, "$label count" );
}

sub test_sentences_field_count($)
{
    my ( $db ) = @_;

    my $label = "setences/field_count";

    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "$label:$label" );

    my $stories = $db->query( "select * from stories order by stories_id asc limit 10" )->hashes;
    my $tagged_stories = [ ( @{ $stories } )[ 1 .. 5 ] ];
    for my $story ( @{ $tagged_stories } )
    {
        $db->query( <<SQL, $story->{ stories_id }, $tag->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
SQL
    }

    my $stories_ids = [ map { $_->{ stories_id } } @{ $stories } ];
    my $stories_ids_list = join( ' ', @{ $stories_ids } );

    my $tagged_stories_ids = [ map { $_->{ stories_id } } @{ $tagged_stories } ];

    my $r = test_get( '/api/v2/sentences/field_count',
        { field => 'tags_id_stories', q => "stories_id:($stories_ids_list)", tag_sets_id => $tag->{ tag_sets_id } } );

    is( scalar( @{ $r } ), 1, "$label num of tags" );

    my $got_tag = $r->[ 0 ];
    is( $got_tag->{ count }, scalar( @{ $tagged_stories } ), "$label count" );
    map { is( $got_tag->{ $_ }, $tag->{ $_ }, "$label field '$_'" ) } ( qw/tag tags_id label tag_sets_id/ );
}

sub test_sentences_list($)
{
    my ( $db ) = @_;

    my $label = "setences/list";

    my $stories     = $db->query( "select * from stories order by stories_id asc limit 10" )->hashes;
    my $stories_ids = [ map { $_->{ stories_id } } @{ $stories } ];
    my $ss          = $db->query( 'select * from story_sentences where stories_id in ( ?? )', @{ $stories_ids } )->hashes;

    my $stories_ids_list = join( ' ', @{ $stories_ids } );
    my $r = test_get( '/api/v2/sentences/list', { q => "stories_id:($stories_ids_list) and sentence:[* TO *]" } );

    is( $r->{ response }->{ numFound }, scalar( @{ $ss } ), "$label num found" );

    my $fields = [ qw/stories_id media_id sentence language publish_date/ ];
    rows_match( $label, $r->{ response }->{ docs }, $ss, 'story_sentences_id', $fields );
}

sub test_sentences($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    MediaWords::Test::DB::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    test_sentences_count( $db );
    test_sentences_field_count( $db );
    test_sentences_list( $db );
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_sentences,
        [ 'solr_standalone', 'job_broker:rabbitmq', 'rescrape_media' ] );

    done_testing();
}

main();
