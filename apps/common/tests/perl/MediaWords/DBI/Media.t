use strict;
use warnings;

# tests for MediaWords::DBI::Media

use Readonly;
use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Media;
use MediaWords::Test::DB::Create;

# test that medium_is_ready_for_analysis returns false when there are few than 100 stories and they are recent
sub test_few_recent_stories($)
{
    my ( $db ) = @_;

    my $label = 'few recent stories';

    my $test_stack = MediaWords::Test::DB::Create::create_test_story_stack(
        $db,
        {
            "$label medium" => {
                "feed" => [
                    'story',
                ]
            }
        }
    );

    my $medium = $test_stack->{ "$label medium" };

    $db->query( "UPDATE feeds SET active = 't' WHERE media_id = \$1", $medium->{ media_id } );

    $db->query( <<SQL,
        WITH stories_to_update AS (
            SELECT stories_id
            FROM stories
            WHERE media_id = \$1
        )
        UPDATE stories SET
            collect_date = NOW()
        WHERE stories_id IN (
            SELECT stories_id
            FROM stories_to_update
        )
SQL
        $medium->{ media_id }
    );

    ok( !MediaWords::DBI::Media::medium_is_ready_for_analysis( $db, $medium ), $label );
}

# test that medium_is_ready_for_analysis returns false when there is a single story if that story is old
sub test_few_old_stories($)
{
    my ( $db ) = @_;

    my $label = 'few old stories';

    my $test_stack = MediaWords::Test::DB::Create::create_test_story_stack(
        $db,
        {
            "$label medium" => {
                "feed" => [
                    'story',
                ]
            }
        }
    );

    my $medium = $test_stack->{ "$label medium" };

    $db->query( "UPDATE feeds SET active = 't' WHERE media_id = \$1", $medium->{ media_id } );

    $db->query( <<SQL,
        WITH stories_to_update AS (
            SELECT stories_id
            FROM stories
            WHERE media_id = ?
        )
        UPDATE stories SET
            publish_date = NOW() - '1 year'::interval
        WHERE stories_id IN (
            SELECT stories_id
            FROM stories_to_update
        )
SQL
        $medium->{ media_id }
    );

    ok( !MediaWords::DBI::Media::medium_is_ready_for_analysis( $db, $medium ), $label );
}

# test that the medium_is_ready_for_analysis returns false when there are no stories
sub test_no_stories($)
{
    my ( $db ) = @_;

    my $label = 'no stories';

    my $test_stack = MediaWords::Test::DB::Create::create_test_story_stack(
        $db,
        {
            "$label medium" => {
                "feed" => []
            }
        }
    );

    my $medium = $test_stack->{ "$label medium" };

    $db->query( "UPDATE feeds SET active = 't' WHERE media_id = \$1", $medium->{ media_id } );

    ok( !MediaWords::DBI::Media::medium_is_ready_for_analysis( $db, $medium ), $label );
}

# test that the medium_is_ready_for_analysis returns false when there are few than 100 stories and
# there is no active feed
sub test_no_active_feed($)
{
    my ( $db ) = @_;

    my $label = 'no active feed';

    my $test_stack = MediaWords::Test::DB::Create::create_test_story_stack(
        $db,
        {
            "$label medium" => {
                "feed" => [
                    'story',
                ]
            }
        }
    );

    my $medium = $test_stack->{ "$label medium" };

    $db->query( "UPDATE feeds SET active = 'f' WHERE media_id = \$1", $medium->{ media_id } );

    $db->query( <<SQL,
        WITH stories_to_update AS (
            SELECT stories_id
            FROM stories
            WHERE media_id = ?
        )
        UPDATE stories SET
            publish_date = NOW() - '1 year'::interval
        WHERE stories_id IN (
            SELECT stories_id
            FROM stories_to_update
        )
SQL
        $medium->{ media_id }
    );

    ok( !MediaWords::DBI::Media::medium_is_ready_for_analysis( $db, $medium ), $label );
}

sub test_medium_is_ready_for_analysis
{
    my ( $db ) = @_;

    test_few_recent_stories( $db );
    test_few_old_stories( $db );
    test_no_active_feed( $db );
    test_no_stories( $db );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_medium_is_ready_for_analysis( $db );

    done_testing();
}

main();
