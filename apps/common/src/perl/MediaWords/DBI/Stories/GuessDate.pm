package MediaWords::DBI::Stories::GuessDate;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Tags;

# confirm that the date for the story is correct by changing the date_guess_method of the given
# story to 'manual'
sub confirm_date
{
    my ( $db, $story ) = @_;

    # MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK
    $db->query( <<SQL,
        DELETE FROM unsharded_public.stories_tags_map
        WHERE
            stories_id = ? AND
            tags_id IN (
                SELECT tags.tags_id
                FROM tag_sets
                    INNER JOIN tags
                        ON tag_sets.tag_sets_id = tags.tag_sets_id
                WHERE tag_sets.name = 'date_guess_method'
            )
SQL
        $story->{ stories_id }
    );
    $db->query( <<SQL,
        DELETE FROM sharded_public.stories_tags_map
        WHERE
            stories_id = ? AND
            tags_id IN (
                SELECT tags.tags_id
                FROM tag_sets
                    INNER JOIN tags
                        ON tag_sets.tag_sets_id = tags.tag_sets_id
                WHERE tag_sets.name = 'date_guess_method'
            )
SQL
        $story->{ stories_id }
    );

    my $t = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:manual' );
    $db->query( <<SQL,
        INSERT INTO stories_tags_map (stories_id, tags_id)
        VALUES (?, ?)
SQL
        $story->{ stories_id }, $t->{ tags_id }
    );
}

# if the date guess method is manual, remove and replace with an ;unconfirmed' method tag
sub unconfirm_date
{
    my ( $db, $story ) = @_;

    unless ( date_is_confirmed( $db, $story ) )
    {
        WARN "Date for story " . $story->{ stories_id } . " is not confirmed, so not unconfirming.";
        return;
    }

    my $manual      = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:manual' );
    my $unconfirmed = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:unconfirmed' );

    # MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK
    $db->query( <<SQL,
        DELETE FROM unsharded_public.stories_tags_map
        WHERE
            stories_id = ? AND
            tags_id = ?
SQL
        $story->{ stories_id }, $manual->{ tags_id }
    );
    $db->query( <<SQL,
        DELETE FROM sharded_public.stories_tags_map
        WHERE
            stories_id = ? AND
            tags_id = ?
SQL
        $story->{ stories_id }, $manual->{ tags_id }
    );

    $db->query( <<SQL,
        INSERT INTO stories_tags_map (stories_id, tags_id)
        VALUES (?, ?)
SQL
        $story->{ stories_id }, $unconfirmed->{ tags_id }
    );

}

# return true if the date guess method is manual, which means that the date has been confirmed
sub date_is_confirmed
{
    my ( $db, $story ) = @_;

    my $r = $db->query( <<SQL,
        SELECT 1
        FROM
            stories_tags_map AS stm,
            tags AS t,
            tag_sets AS ts
        WHERE
            stm.tags_id = t.tags_id AND
            ts.tag_sets_id = t.tag_sets_id AND
            t.tag = 'manual' AND
            ts.name = 'date_guess_method' AND
            stm.stories_id = ?
SQL
        $story->{ stories_id }
    )->hash;

    return $r ? 1 : 0;
}

# for each story in $stories set { date_is_reliable }.
#
# a date is reliable if either of the following are true:
# * the story has one of the date_guess_method tags listed in reliable_methods below;
# * no date_guess_method tag and no date_invalid:undateable tag is associated with the story
#
# otherwise, the date is unreliable
sub add_date_is_reliable_to_stories
{
    my ( $db, $stories ) = @_;

    my $ids_table = $db->get_temporary_ids_table( [ map { int( $_->{ stories_id } ) } @{ $stories } ] );

    my $reliable_methods =
      [ qw/guess_by_og_article_published_time guess_by_url guess_by_url_and_date_text merged_story_rss manual/ ];
    my $quoted_reliable_methods_list = join( ',', map { $db->quote( $_ ) } @{ $reliable_methods } );

    my $date_tag_sets_ids = $db->query( <<SQL
        SELECT tag_sets_id
        FROM tag_sets
        WHERE name IN ('date_guess_method', 'date_invalid')
SQL
    )->flat();

    # the query below errors in tests if date_tag_sets_ids is empty
    push( @{ $date_tag_sets_ids }, -1 );

    my $date_tag_sets_ids_list = join( ',', map { int( $_ ) } @{ $date_tag_sets_ids } );

    $db->query( <<SQL
        CREATE TEMPORARY TABLE _date_tags AS
            SELECT
                t.*,
                ts.name AS tag_set_name
            FROM tags AS t
                JOIN tag_sets AS ts
                    ON t.tag_sets_id = ts.tag_sets_id
            WHERE t.tag_sets_id IN ($date_tag_sets_ids_list)
SQL
    );

    $db->query( <<SQL
        CREATE TEMPORARY TABLE _story_date_tags AS
            SELECT
                stories_id,
                t.tag,
                t.tag_set_name
            FROM stories_tags_map AS stm
                LEFT JOIN _date_tags AS t
                    ON t.tags_id = stm.tags_id
            WHERE stm.stories_id IN (
                SELECT id
                FROM $ids_table
            )
SQL
    );

    my $reliable_stories_ids = $db->query( <<SQL
        SELECT id AS stories_id
        FROM $ids_table AS ids
        WHERE
            EXISTS (
                SELECT 1
                FROM _story_date_tags AS d
                WHERE
                    d.stories_id = ids.id AND
                    d.tag IN ($quoted_reliable_methods_list)
            ) OR
            (
                EXISTS (
                    SELECT 1
                    FROM _story_date_tags AS d
                    WHERE
                        d.stories_id = ids.id AND
                        d.tag = 'undateable'
                ) AND
                NOT EXISTS (
                    SELECT 1
                    FROM _story_date_tags AS d
                    WHERE
                        d.stories_id = ids.id AND
                        d.tag_set_name = 'date_guess_method'
                )
            )
SQL
    )->flat;

    my $reliable_stories_lookup = {};
    map { $reliable_stories_lookup->{ $_ } = 1 } @{ $reliable_stories_ids };

    map { $_->{ date_is_reliable } = ( $reliable_stories_lookup->{ $_->{ stories_id } } || 0 ) } @{ $stories };
}

# set the undateable status of the story by adding or removing the 'date_guess_method:undateable' tage
sub mark_undateable
{
    my ( $db, $story, $undateable ) = @_;

    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_invalid:undateable' );

    # MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK
    $db->query( <<SQL,
        DELETE FROM unsharded_public.stories_tags_map
        WHERE
            stories_id = ? AND
            tags_id IN (
                SELECT tags.tags_id
                FROM tag_sets
                    INNER JOIN tags
                        ON tag_sets.tag_sets_id = tags.tag_sets_id
                WHERE tag_sets.name = 'date_invalid'
            )
SQL
        $story->{ stories_id }
    );
    $db->query( <<SQL,
        DELETE FROM sharded_public.stories_tags_map
        WHERE
            stories_id = ? AND
            tags_id IN (
                SELECT tags.tags_id
                FROM tag_sets
                    INNER JOIN tags
                        ON tag_sets.tag_sets_id = tags.tag_sets_id
                WHERE tag_sets.name = 'date_invalid'
            )
SQL
        $story->{ stories_id }
    );

    if ( $undateable )
    {
        $db->query( <<SQL,
            INSERT INTO stories_tags_map (stories_id, tags_id)
            VALUES (?, ?)
SQL
        $story->{ stories_id }, $tag->{ tags_id }
    );
    }
}

sub is_undateable
{
    my ( $db, $story ) = @_;

    my $tag = $db->query( <<SQL,
        SELECT 1
        FROM stories_tags_map AS stm
            JOIN tags AS t
                ON stm.tags_id = t.tags_id
            JOIN tag_sets AS ts
                ON t.tag_sets_id = ts.tag_sets_id
        WHERE
            stm.stories_id = ? AND
            ts.name = 'date_invalid' AND
            t.tag = 'undateable'
SQL
        $story->{ stories_id }
    )->hash;

    return $tag ? 1 : 0;
}

# add { undateable } field to a list of stories
sub add_undateable_to_stories($$)
{
    my ( $db, $stories ) = @_;

    my $ids_table = $db->get_temporary_ids_table( [ map { int( $_->{ stories_id } ) } @{ $stories } ] );

    $db->query( <<SQL
        CREATE TEMPORARY TABLE _stm AS
            SELECT
                stories_id,
                tags_id
            FROM stories_tags_map
            WHERE stories_id IN (
                SELECT id
                FROM $ids_table
            )
SQL
    );

    my $undateable_stories_ids = $db->query( <<SQL
        SELECT stories_id
        FROM _stm AS stm
            JOIN tags AS t
                ON stm.tags_id = t.tags_id
            JOIN tag_sets AS ts
                ON t.tag_sets_id = ts.tag_sets_id
        WHERE
            ts.name = 'date_invalid' AND
            t.tag = 'undateable'
SQL
    )->flat;

    my $undateable_stories_id_lookup = {};
    map { $undateable_stories_id_lookup->{ $_ } = 1 } @{ $undateable_stories_ids };

    map { $_->{ undateable } = $undateable_stories_id_lookup->{ $_->{ stories_id } } || 0 } @{ $stories };
}

# return true if the story has been marked as undateable
sub is_undatable($$)
{
    my ( $db, $story ) = @_;

    # do goofy story copy voodoo so that we can reuse add_undateable_to_stories(), which is efficient for many stories

    my $story_copy = { stories_ids => $story->{ stories_id } };

    add_undatable_to_stories( $db, [ $story_copy ] );

    return $story_copy->{ undateable };
}

my $_date_guess_method_tag_lookup = {};

# assign a tag to the story for the date guess method
sub assign_date_guess_method
{
    my ( $db, $story, $date_guess_method, $no_delete ) = @_;

    if ( !$no_delete )
    {
        for my $tag_set_name ( 'date_guess_method', 'date_invalid' )
        {
            # MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK
            $db->query( <<SQL,
                DELETE FROM unsharded_public.stories_tags_map
                WHERE
                    stories_id = ? AND
                    tags_id IN (
                        SELECT tags.tags_id
                        FROM tag_sets
                            INNER JOIN tags
                                ON tag_sets.tag_sets_id = tags.tag_sets_id
                        WHERE tag_sets.name = ?
                    )
SQL
                $story->{ stories_id }, $tag_set_name
            );
            $db->query( <<SQL,
                DELETE FROM sharded_public.stories_tags_map
                WHERE
                    stories_id = ? AND
                    tags_id IN (
                        SELECT tags.tags_id
                        FROM tag_sets
                            INNER JOIN tags
                                ON tag_sets.tag_sets_id = tags.tag_sets_id
                        WHERE tag_sets.name = ?
                    )
SQL
                $story->{ stories_id }, $tag_set_name
            );
        }
    }

    my $tag_name = ( $date_guess_method eq 'undateable' ) ? 'date_invalid:undateable' : 'date_guess_method:unknown';

    my $date_guess_method_tag = $_date_guess_method_tag_lookup->{ $tag_name };
    if ( !$date_guess_method_tag )
    {
        $date_guess_method_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, $tag_name );
        $_date_guess_method_tag_lookup->{ $tag_name } = $date_guess_method_tag;
    }

    $db->query( <<SQL,
        INSERT INTO stories_tags_map (stories_id, tags_id)
        VALUES (?, ?)
SQL
        $story->{ stories_id }, $date_guess_method_tag->{ tags_id }
    );

}

1;
