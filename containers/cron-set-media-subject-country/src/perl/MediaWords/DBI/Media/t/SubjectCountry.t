use strict;
use warnings;

# tests for MediaWords::DBI::Media::SubjectCountry

use MediaWords::CommonLibs;

use Readonly;
use Test::More;

use MediaWords::DBI::Media;
use MediaWords::DBI::Media::SubjectCountry;

# test that the given medium has the given subject country tag
sub test_medium_country_tag($$$$)
{
    my ( $label, $db, $medium, $country ) = @_;

    my $tag_set = MediaWords::DBI::Media::SubjectCountry::get_subject_country_tag_set( $db );

    my $tags = $db->query( <<SQL, $medium->{ media_id }, $tag_set->{ tag_sets_id } )->hashes;
select t.*
    from media_tags_map mtm
        join tags t using ( tags_id )
    where
        mtm.media_id = \$1 and
        t.tag_sets_id = \$2
SQL

    if ( !$country )
    {
        is( scalar( @{ $tags } ), 0, "$label number of tags" );
        return;
    }

    is( scalar( @{ $tags } ),    1,        "$label number of tags" );
    is( $tags->[ 0 ]->{ tag },   $country, "$label country tag" );
    is( $tags->[ 0 ]->{ label }, $country, "$label country label" );
}

# add a GEOTAG_TAG_SET_NAME tag with the given country label to the given number of stories in the given medium
sub add_country_geo_tags($$$$)
{
    my ( $db, $medium, $country, $num_stories ) = @_;

    my $tag_set_name = $MediaWords::DBI::Media::SubjectCountry::GEOTAG_TAG_SET_NAME;
    my $tag_set = $db->find_or_create( 'tag_sets', { name => $tag_set_name } );

    my $tag_sets_id = $tag_set->{ tag_sets_id };
    my $tag = $db->find_or_create( 'tags', { tag => $country, label => $country, tag_sets_id => $tag_sets_id } );

    my $stories = $db->query( "select * from stories where media_id = \$1", $medium->{ media_id } )->hashes;

    my $i = 0;
    for my $story ( @{ $stories } )
    {
        my $insert_tags_id;
        if ( $i++ < $num_stories )
        {
            $insert_tags_id = $tag->{ tags_id };
        }
        else
        {
            my $t = $story->{ stories_id } . '';    # use stringified stories_id to make sure other tags are unique
            my $other_tag = $db->find_or_create( 'tags', { tag => $t, label => $t, tag_sets_id => $tag_sets_id } );
            $insert_tags_id = $other_tag->{ tags_id };
        }

        $db->query( <<SQL, $insert_tags_id, $story->{ stories_id } );
insert into stories_tags_map ( tags_id, stories_id ) values ( \$1, \$2 )
SQL
    }
}

# test that the country gets set correctly by setting the given number of stories to the given country
# and testing that the subject country is set to $proportion if $proportion is > 0.5 and 'none' otherwise
sub test_medium_country($$$)
{
    my ( $db, $country, $country_proportion ) = @_;

    my $label = "medium country $country proportion $country_proportion";

    my $num_stories = 200;

    my $stories = [ 1 .. $num_stories ];

    my $test_stack =
      MediaWords::Test::DB::Create::create_test_story_stack( $db, { "$label medium" => { "feed" => $stories } } );

    my $medium = $test_stack->{ "$label medium" };

    my $media_id = $medium->{ media_id };

    my $num_country_stories = int( $num_stories * $country_proportion );

    add_country_geo_tags( $db, $medium, $country, $num_country_stories );

    MediaWords::DBI::Media::SubjectCountry::set_subject_country( $db, $medium );

    my $expected_subject_country = ( $country_proportion > 0.5 ) ? $country : 'none';

    test_medium_country_tag( $label, $db, $medium, $expected_subject_country );
}

sub test_media_subject_country
{
    my ( $db ) = @_;

    test_medium_country( $db, 'Russia',  1 );
    test_medium_country( $db, 'Spain',   1 );
    test_medium_country( $db, 'England', 0.51 );
    test_medium_country( $db, 'France',  0.4 );
    test_medium_country( $db, 'Ghana',   0 );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_media_subject_country( $db );

    done_testing();
}

main();
