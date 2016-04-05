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

    $db->query( <<END, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t, tag_sets ts
    where t.tag_sets_id = ts.tag_sets_id and
        stm.tags_id = t.tags_id and
        ts.name = 'date_guess_method' and
        stm.stories_id = ?
END

    my $t = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:manual' );
    $db->query( <<END, $story->{ stories_id }, $t->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END
}

# if the date guess method is manual, remove and replace with an ;unconfirmed' method tag
sub unconfirm_date
{
    my ( $db, $story ) = @_;

    unless ( date_is_confirmed( $db, $story ) )
    {
        say STDERR "Date for story " . $story->{ stories_id } . " is not confirmed, so not unconfirming.";
        return;
    }

    my $manual      = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:manual' );
    my $unconfirmed = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:unconfirmed' );

    $db->query( <<END, $story->{ stories_id }, $manual->{ tags_id } );
delete from stories_tags_map where stories_id = ? and tags_id = ?
END

    $db->query( <<END, $story->{ stories_id }, $unconfirmed->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END

}

# return true if the date guess method is manual, which means that the date has been confirmed
sub date_is_confirmed
{
    my ( $db, $story ) = @_;

    my $r = $db->query( <<END, $story->{ stories_id } )->hash;
select 1 from stories_tags_map stm, tags t, tag_sets ts
    where stm.tags_id = t.tags_id and
        ts.tag_sets_id = t.tag_sets_id and
        t.tag = 'manual' and
        ts.name = 'date_guess_method' and
        stm.stories_id = ?
END

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

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    my $reliable_methods =
      [ qw/guess_by_og_article_published_time guess_by_url guess_by_url_and_date_text merged_story_rss manual/ ];
    my $quoted_reliable_methods_list = join( ',', map { $db->dbh->quote( $_ ) } @{ $reliable_methods } );

    my $reliable_stories_ids = $db->query( <<SQL )->flat;
with date_tags as (
    select t.*, ts.name tag_set_name
        from tags t
            join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
            where ts.name in ( 'date_guess_method', 'date_invalid' )
),

story_date_tags as (
    select stories_id, t.tag, t.tag_set_name
        from stories_tags_map stm
            left join date_tags t on ( t.tags_id = stm.tags_id )
        where stm.stories_id in ( select id from $ids_table )
)

select id stories_id
    from $ids_table ids
    where
        exists (
            select 1
                from story_date_tags d
                where
                    d.stories_id = ids.id and
                    d.tag in ( $quoted_reliable_methods_list )
        ) or
        (
            exists (
                select 1
                    from story_date_tags d
                    where
                        d.stories_id = ids.id and
                        d.tag = 'undateable'
            ) and
            not exists (
                select 1
                    from story_date_tags d
                    where
                        d.stories_id = ids.id and
                        d.tag_set_name = 'date_guess_method'
            )
        )
SQL

    my $reliable_stories_lookup = {};
    map { $reliable_stories_lookup->{ $_ } = 1 } @{ $reliable_stories_ids };

    map { $_->{ date_is_reliable } = ( $reliable_stories_lookup->{ $_->{ stories_id } } || 0 ) } @{ $stories };
}

# set the undateable status of the story by adding or removing the 'date_guess_method:undateable' tage
sub mark_undateable
{
    my ( $db, $story, $undateable ) = @_;

    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_invalid:undateable' );

    $db->query( <<END, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where
        t.tags_id = stm.tags_id and
        ts.name = 'date_invalid' and
        stories_id = ?
END

    if ( $undateable )
    {
        $db->query( <<END, $story->{ stories_id }, $tag->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END
    }
}

sub is_undateable
{
    my ( $db, $story ) = @_;

    my $tag = $db->query( <<END, $story->{ stories_id } )->hash;
select 1
    from stories_tags_map stm
        join tags t on ( stm.tags_id = t.tags_id )
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where
        stm.stories_id = ? and
        ts.name = 'date_invalid' and
        t.tag = 'undateable'
END

    return $tag ? 1 : 0;
}

# add { undateable } field to a list of stories
sub add_undateable_to_stories($$)
{
    my ( $db, $stories ) = @_;

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    my $undateable_stories_ids = $db->query( <<SQL );
select stories_id
    from stories_tags_map stm
        join tags t on ( stm.tags_id = t.tags_id )
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where
        stm.stories_id in ( select id from $ids_table ) and
        ts.name = 'date_invalid' and
        t.tag = 'undateable'
SQL
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
            $db->query( <<END, $tag_set_name, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where
        t.tags_id = stm.tags_id and
        ts.name = ? and
        stm.stories_id = ?
END
        }
    }

    my $tag_set_name = ( $date_guess_method eq 'undateable' ) ? 'date_invalid' : 'date_guess_method';
    my $tag_name = "$tag_set_name:$date_guess_method";

    my $date_guess_method_tag = $_date_guess_method_tag_lookup->{ $tag_name };
    if ( !$date_guess_method_tag )
    {
        $date_guess_method_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "$tag_set_name:$date_guess_method" );
        $_date_guess_method_tag_lookup->{ $tag_name } = $date_guess_method_tag;
    }

    $db->query( <<END, $story->{ stories_id }, $date_guess_method_tag->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END

}

1;
