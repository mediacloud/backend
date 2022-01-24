use strict;
use warnings;

# tests for MediaWords::DBI::Media::PrimaryLanguage

use Readonly;
use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Media;
use MediaWords::DBI::Media::PrimaryLanguage;
use MediaWords::Test::DB::Create;

# test that the given medium has the given language tag
sub test_medium_language_tag($$$$)
{
    my ( $label, $db, $medium, $code ) = @_;

    my $tag_set = MediaWords::DBI::Media::PrimaryLanguage::get_primary_language_tag_set( $db );

    my $tags = $db->query( <<SQL,
        SELECT t.*
        FROM media_tags_map AS mtm
            INNER JOIN tags AS t USING (tags_id)
        WHERE
            mtm.media_id = \$1 AND
            t.tag_sets_id = \$2
SQL
        $medium->{ media_id }, $tag_set->{ tag_sets_id }
    )->hashes;

    if ( !$code )
    {
        is( scalar( @{ $tags } ), 0, "$label number of tags" );
        return;
    }

    is( scalar( @{ $tags } ),  1,     "$label number of tags" );
    is( $tags->[ 0 ]->{ tag }, $code, "$label language" );
}

# test that the primary_language gets set correctly by setting the given number of stories to the given language
# and testing that primary_language is set to $language if $language_proportion is > 0.5 and 'none' otherwise
sub test_medium_language($$$)
{
    my ( $db, $language, $language_proportion ) = @_;

    my $label = "medium language $language proportion $language_proportion";

    my $num_stories = 200;

    my $stories = [ 1 .. 200 ];

    my $test_stack = MediaWords::Test::DB::Create::create_test_story_stack(
        $db,
        {
            "$label medium" => {
                "feed" => $stories,
            }
        }
    );

    my $medium = $test_stack->{ "$label medium" };

    my $media_id = $medium->{ media_id };

    my $num_language_stories = int( $num_stories * $language_proportion );

    $db->query( <<SQL,
        WITH stories_to_update AS (
            SELECT stories_id
            FROM stories
            WHERE media_id = \$1
        )
        UPDATE stories SET
            language = stories_id::TEXT
        WHERE stories_id IN (
            SELECT stories_id
            FROM stories_to_update
        )
SQL
        $media_id
    );

    $db->query( <<SQL,
        WITH stories_to_update AS (
            SELECT stories_id
            FROM stories
            WHERE media_id = \$1
            LIMIT \$3
        )
        UPDATE stories SET
            language = \$2
        WHERE stories_id IN (
            SELECT stories_id
            FROM stories_to_update
        )
SQL
        $media_id, $language, $num_language_stories
    );

    MediaWords::DBI::Media::PrimaryLanguage::set_primary_language( $db, $medium );

    my $expected_primary_language = ( $language_proportion > 0.5 ) ? $language : 'none';

    test_medium_language_tag( $label, $db, $medium, $expected_primary_language );
}

sub test_media_primary_language
{
    my ( $db ) = @_;

    test_medium_language( $db, 'en', 1 );
    test_medium_language( $db, 'es', 1 );
    test_medium_language( $db, 'en', 0.51 );
    test_medium_language( $db, 'es', 0.4 );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_media_primary_language( $db );

    done_testing();
}

main();
