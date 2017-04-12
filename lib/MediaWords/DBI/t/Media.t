use strict;
use warnings;

# tests for MediaWords::DBI::Media::Health

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Readonly;
use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Media;
use MediaWords::Test::DB;

# test that the given medium has the given language tag
sub test_medium_language_tag($$$$)
{
    my ( $label, $db, $medium, $code ) = @_;

    my $tag_set = MediaWords::DBI::Media::_get_primary_language_tag_set( $db );

    my $tags = $db->query( <<SQL, $medium->{ media_id }, $tag_set->{ tag_sets_id } )->hashes;
select t.*
    from media_tags_map mtm
        join tags t using ( tags_id )
    where
        mtm.media_id = \$1 and
        t.tag_sets_id = \$2
SQL

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

    my $test_stack = MediaWords::Test::DB::create_test_story_stack( $db, { "$label medium" => { "feed" => $stories } } );

    my $medium = $test_stack->{ "$label medium" };

    my $media_id = $medium->{ media_id };

    my $num_language_stories = int( $num_stories * $language_proportion );

    $db->query( "update stories set language = ( ( random() * 100 )::int )::text where media_id = \$1", $media_id );

    $db->query( <<SQL, $media_id, $language, $num_language_stories );
update stories set language = \$2
where stories_id in ( select stories_id from stories where media_id = \$1 limit \$3 )
SQL

    MediaWords::DBI::Media::set_primary_language( $db, $medium );

    my $expected_primary_language = ( $language_proportion > 0.5 ) ? $language : 'none';

    test_medium_language_tag( $label, $db, $medium, $expected_primary_language );
}

# test that the medium primary_language remains null when there are few than 100 stories and they are recent
sub test_medium_language_few_recent_stories($)
{
    my ( $db ) = @_;

    my $label = 'few recent stories';

    my $test_stack = MediaWords::Test::DB::create_test_story_stack( $db, { "$label medium" => { "feed" => [ 'story' ] } } );

    my $medium = $test_stack->{ "$label medium" };

    $db->query( "update feeds set feed_status = 'active' where media_id = \$1", $medium->{ media_id } );

    $db->query( "update stories set language = 'en', collect_date = now() where media_id = \$1", $medium->{ media_id } );

    MediaWords::DBI::Media::set_primary_language( $db, $medium );

    $medium = $db->find_by_id( 'media', $medium->{ media_id } );

    test_medium_language_tag( $label, $db, $medium, undef );
}

# test that the medium primary_language gets set to the language if a single story if that story is old
sub test_medium_language_few_old_stories($)
{
    my ( $db ) = @_;

    my $label = 'few old stories';

    my $test_stack = MediaWords::Test::DB::create_test_story_stack( $db, { "$label medium" => { "feed" => [ 'story' ] } } );

    my $medium = $test_stack->{ "$label medium" };

    $db->query( "update feeds set feed_status = 'active' where media_id = \$1", $medium->{ media_id } );

    $db->query( <<SQL, $medium->{ media_id } );
update stories set language = 'fr', publish_date = now() - '1 year'::interval  where media_id = \$1
SQL

    MediaWords::DBI::Media::set_primary_language( $db, $medium );

    test_medium_language_tag( $label, $db, $medium, 'fr' );
}

# test that the medium primary_language remains null when there are no stories
sub test_medium_language_no_stories($)
{
    my ( $db ) = @_;

    my $label = 'no stories';

    my $test_stack = MediaWords::Test::DB::create_test_story_stack( $db, { "$label medium" => { "feed" => [] } } );

    my $medium = $test_stack->{ "$label medium" };

    $db->query( "update feeds set feed_status = 'active' where media_id = \$1", $medium->{ media_id } );

    MediaWords::DBI::Media::set_primary_language( $db, $medium );

    test_medium_language_tag( $label, $db, $medium, undef );
}

# test that the medium primary_language remains null when there are few than 100 stories and they are recent
sub test_medium_language_no_active_feed($)
{
    my ( $db ) = @_;

    my $label = 'no active feed';

    my $test_stack = MediaWords::Test::DB::create_test_story_stack( $db, { "$label medium" => { "feed" => [ 'story' ] } } );

    my $medium = $test_stack->{ "$label medium" };

    $db->query( "update feeds set feed_status = 'inactive' where media_id = \$1", $medium->{ media_id } );

    $db->query( <<SQL, $medium->{ media_id } );
update stories set language = 'fr', publish_date = now() - '1 year'::interval  where media_id = \$1
SQL

    MediaWords::DBI::Media::set_primary_language( $db, $medium );

    test_medium_language_tag( $label, $db, $medium, undef );
}

sub test_media_primary_language
{
    my ( $db ) = @_;

    test_medium_language( $db, 'en', 1 );
    test_medium_language( $db, 'es', 1 );
    test_medium_language( $db, 'en', 0.51 );
    test_medium_language( $db, 'es', 0.4 );

    test_medium_language_few_recent_stories( $db );
    test_medium_language_few_old_stories( $db );
    test_medium_language_no_active_feed( $db );
    test_medium_language_no_stories( $db );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            use Encode;
            my ( $db ) = @_;

            test_media_primary_language( $db );
        }
    );

    done_testing();
}

main();
